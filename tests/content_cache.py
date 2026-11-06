"""Verify query-specific HxWell file-cache hits and expiration against SQLite."""

from concurrent.futures import ThreadPoolExecutor
import hashlib
import http.client
import json
import struct
import time


def request(port, route):
    client = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
    try:
        client.request(
            "GET",
            route,
            headers={
                "X-Inertia": "true",
                "Accept": "application/json",
                "Accept-Encoding": "identity",
            },
        )
        response = client.getresponse()
        return (
            response.status,
            dict((key.lower(), value) for key, value in response.getheaders()),
            response.read().decode(),
        )
    finally:
        client.close()


def cache_key(file):
    raw = file.read_bytes()
    if not raw.startswith(b"HXWELL\x01") or len(raw) < 19:
        return ""
    length = struct.unpack_from("<i", raw, 15)[0]
    return raw[19 : 19 + length].decode()


def content_entries(folder):
    entries = {}
    for file in folder.iterdir():
        if not file.is_file():
            continue
        key = cache_key(file)
        if key.startswith("cms:content:v5:") and len(key.split(":")) == 8:
            entries[key] = file
    return entries


def clear_content(folder):
    for file in folder.iterdir():
        if file.is_file() and cache_key(file).startswith("cms:content:v5:"):
            file.unlink()


def stamps(folder):
    return {
        key: (file.name, file.stat().st_mtime_ns) for key, file in content_entries(folder).items()
    }


def find_entry(folder, domain, operation, parameters):
    digest = hashlib.md5(
        json.dumps(parameters, separators=(",", ":"), ensure_ascii=False).encode()
    ).hexdigest()
    matches = [
        file
        for key, file in content_entries(folder).items()
        if key.split(":")[4] == domain and key.split(":")[6:] == [operation, digest]
    ]
    assert matches, f"Missing specific cache: {operation}"
    return max(matches, key=lambda file: file.stat().st_mtime_ns)


def expire(file):
    raw = bytearray(file.read_bytes())
    struct.pack_into("<d", raw, 7, time.time() - 60)
    file.write_bytes(raw)


def verify(port, fixtures, cache_folder):
    content = "/content/welcome-to-haxepress"
    routes = [
        ("/", 200),
        ("/content?q=media&category=Content%20management", 200),
        (content, 200),
        ("/about", 200),
        ("/rss.xml", 200),
        ("/content/no-such-cached-content", 404),
        ("/content/your-next-content-item", 404),
        ("/categories/options?q=Liv", 200),
    ]
    for route, expected in routes:
        assert request(port, route)[0] == expected
    entries = content_entries(cache_folder)
    operations = {key.split(":")[6] for key in entries}
    assert {
        "featured",
        "home-latest",
        "index",
        "content-count",
        "published-by-slug",
        "related",
        "rss",
        "options",
        "public",
    } <= operations
    assert all(key.split(":")[6] not in {"items", "all"} for key in entries)
    before = stamps(cache_folder)
    with fixtures.guard(blockDatabase=True):
        assert request(port, "/content?q=guard-cold-probe")[0] == 500, "Database guard is inactive"
        for route, expected in routes:
            status, headers, body = request(port, route)
            assert status == expected, f"Warm query accessed the database: {route} {body[:150]}"
            assert "set-cookie" not in headers
    assert stamps(cache_folder) == before
    print(
        "PASS Warm, query-specific pages/details/filters/RSS/options while database access is rejected",
        flush=True,
    )

    conditions = [("slug", "=", "welcome-to-haxepress")]
    original = fixtures.rows("items", ["id", "title"], conditions, limit=1)[0]["title"]
    changed = "A uniquely refreshed cache entry"
    fixtures.update("items", {"title": changed}, conditions)
    try:
        assert json.loads(request(port, content)[2])["props"]["item"]["title"] == original
        fresh = json.loads(request(port, "/content?q=uniquely%20refreshed")[2])
        assert (
            fresh["props"]["items"][0]["title"] == changed
        ), "A new query filtered an old whole-content cache"
        expire(
            find_entry(
                cache_folder, "items", "published-by-slug", ["entry", "welcome-to-haxepress"]
            )
        )
        assert json.loads(request(port, content)[2])["props"]["item"]["title"] == changed
    finally:
        fixtures.update("items", {"title": original}, conditions)
        clear_content(cache_folder)
    print(
        "PASS A new search queries SQLite independently; only the expired detail cache reloads",
        flush=True,
    )

    with ThreadPoolExecutor(max_workers=12) as pool:
        pages = list(pool.map(lambda _: request(port, "/content"), range(12)))
    assert all(
        status == 200 and len(json.loads(body)["props"]["items"]) == 7 for status, _, body in pages
    )
    print("PASS Concurrent cold fills produce complete, bounded query results", flush=True)
