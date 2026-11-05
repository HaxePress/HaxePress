"""Exercise CMS workflows through the real guarded HTTP application."""

import json
import base64
import io
import os
import secrets
import zipfile
from pathlib import Path

from e2e import Client, check
from fixture_store import FixtureStore

HEADERS = {"X-Inertia": "true", "Accept": "application/json"}


def package_archive(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in entries:
            archive.writestr(name, content)
    return base64.b64encode(output.getvalue()).decode()


def verify_packages(fixtures):
    manifest = {
        "apiVersion": 4,
        "cmsVersion": "2.16.0",
        "kind": "plugin",
        "slug": "reading-companion",
        "name": "Reading Companion",
        "version": "2.16.0",
        "description": "A small companion for curious readers.",
        "author": "HaxePress",
        "assets": {"module": "main.mjs"},
        "fields": [
            {
                "key": "message",
                "label": "Message",
                "kind": "text",
                "defaultValue": "Read thoughtfully.",
            }
        ],
    }
    example = Path(__file__).resolve().parents[1] / "Export/packages/reading-companion-2.16.0.zip"
    with zipfile.ZipFile(example) as sample:
        jar = sample.read("server.jar")
        cppia = sample.read("server.cppia")
    manifest["server"] = {
        "jar": "server.jar",
        "cppia": "server.cppia",
        "entrypoint": "example.reading.ReadingPlugin",
    }
    entries = [
        ("cms-package.json", json.dumps(manifest)),
        ("public/main.mjs", "export function activate() { return () => {}; }"),
        ("server.jar", jar),
        ("server.cppia", cppia),
    ]
    cppia_only = {
        **manifest,
        "server": {"cppia": "server.cppia", "entrypoint": "example.reading.ReadingPlugin"},
    }
    cppia_entries = [
        ("cms-package.json", json.dumps(cppia_only)),
        ("public/main.mjs", "export function activate() {}"),
        ("server.cppia", b"CPPIB\ninvalid"),
    ]
    try:
        fixtures.call("inspect_package", archive=package_archive(cppia_entries))
    except RuntimeError as error:
        check("both" in str(error), "single-target package was not rejected")
    else:
        raise AssertionError("JVM accepted a CPPIA-only server package")
    inspected = fixtures.call("inspect_package", archive=package_archive(entries))
    check(inspected["manifest"]["slug"] == manifest["slug"], "valid plugin manifest")
    check(inspected["manifest"]["hooks"] == ["site.assets"], "asset hooks were not registered")
    nested = [("reading-companion/" + name, content) for name, content in entries]
    check(
        fixtures.call("inspect_package", archive=package_archive(nested))["manifest"]["name"]
        == manifest["name"],
        "single-root package folders are not supported",
    )
    invalid_archives = [
        entries + [("../outside.txt", "outside")],
        entries + [("/tmp/outside.txt", "outside")],
        entries + [("..\\outside.txt", "outside")],
        entries + [("public/Main.mjs", "duplicate")],
        entries + [("large.txt", b"A" * (17 * 1024 * 1024))],
        [("cms-package.json", json.dumps({**manifest, "apiVersion": 999})), entries[1]],
        [("cms-package.json", json.dumps({**manifest, "apiVersion": "1"})), entries[1]],
        [("cms-package.json", json.dumps(manifest))],
    ]
    for invalid in invalid_archives:
        try:
            fixtures.call("inspect_package", archive=package_archive(invalid))
        except RuntimeError:
            pass
        else:
            raise AssertionError("Invalid plugin package was accepted: " + invalid[-1][0])
    work = Path(os.environ["TEST_DB_PATH"]).parent.parent
    check(not (work / "outside.txt").exists(), "package extraction escaped its staging directory")
    example = Path(__file__).resolve().parents[1] / "Export/packages/reading-companion-2.16.0.zip"
    package_data = base64.b64encode(example.read_bytes()).decode()
    message = "A note from an uploaded JVM plugin."
    result = fixtures.call(
        "dispatch_package",
        archive=package_data,
        event="site.shared",
        context={"settings": {"message": message}},
    )
    check(result["blocks"][0]["content"] == message, "uploaded JVM plugin did not execute its hook")
    print(
        "PASS CMS package archives: manifest validation, nested roots, path/duplicate protection and streamed expansion limits",
        flush=True,
    )


def verify_transaction_boundary(fixtures):
    suffix = secrets.token_hex(5)
    keys = []
    try:
        for rollback in [False, True]:
            before = "cms-tx-before-" + str(rollback) + suffix
            after = "cms-tx-after-" + str(rollback) + suffix
            keys.extend([before, after])
            fixtures.call(
                "transaction_boundary", beforeKey=before, afterKey=after, rollback=rollback
            )
            check(
                fixtures.count("settings", [("key", "=", before)]) == (0 if rollback else 1),
                "transaction commit/rollback semantics",
            )
            check(
                fixtures.count("settings", [("key", "=", after)]) == 1,
                "ordinary write after a transaction was rolled back on connection close",
            )
    finally:
        fixtures.delete("settings", [("key", "in", keys)])
    print(
        "PASS CMS transaction boundary: ordinary model writes persist after commit and rollback",
        flush=True,
    )


def props(client, route):
    status, _, body = client.request(route, extra_headers=HEADERS)
    check(status == 200, "CMS page failed: " + route + " " + body[:200])
    return json.loads(body)["props"]


def run():
    with FixtureStore.from_environment() as fixtures:
        verify_transaction_boundary(fixtures)
        verify_packages(fixtures)
        verify_tags(fixtures)


def verify_tags(fixtures):
    admin = Client()
    public = Client()
    admin.request("/admin/login")
    check(
        admin.request(
            "/admin/login",
            "POST",
            {
                "email": os.environ["TEST_ADMIN_EMAIL"],
                "password": os.environ["TEST_ADMIN_PASSWORD"],
            },
        )[0]
        == 303,
        "CMS login",
    )
    suffix = secrets.token_hex(5)
    name = "Mindful days " + suffix
    slug = "mindful-days-" + suffix
    tag = {"name": name, "slug": slug, "description": "Content about a more considered everyday."}
    check(public.request("/admin/tags")[0] == 303, "tags bypassed the admin guard")
    check(
        admin.request("/admin/tags/save", "POST", tag, csrf=False)[0] == 419,
        "tag writes bypassed CSRF",
    )
    check(admin.request("/admin/tags/save", "POST", tag)[0] == 303, "create a tag")
    listing = props(admin, "/admin/tags?q=Mindful%20days")
    created = next(item for item in listing["tags"] if item["slug"] == slug)
    tag_id = created["id"]
    check(created["items"] == 0, "new tag usage")
    try:
        fixtures.create("content_tags", [{"content_id": 1, "tag_id": 99999999}])
    except RuntimeError as error:
        check("FOREIGN" in str(error).upper(), "unexpected relation failure")
    else:
        raise AssertionError("Missing tag references were accepted by the database")
    check(admin.request("/admin/tags/save", "POST", tag)[0] == 422, "duplicate tag accepted")
    invalid = {**tag, "name": name + " invalid", "slug": "bad/path"}
    check(admin.request("/admin/tags/save", "POST", invalid)[0] == 422, "invalid tag slug accepted")

    content_slug = "cms-tagged-content-" + suffix
    content = {
        "title": "A content item connected by an idea",
        "slug": content_slug,
        "excerpt": "A test content item for taxonomy and published archives.",
        "content": "## A considered everyday\n\nA meaningful content item with enough content to publish.",
        "category": props(admin, "/admin/content/new")["item"]["category"],
        "status": "draft",
        "image": "",
        "image_alt": "",
        "featured": "0",
        "published_at": "2026-11-03",
        "tags": str(tag_id),
    }
    content_id = None
    try:
        check(
            admin.request("/admin/content/save", "POST", content)[0] == 303, "save tag assignment"
        )
        stored = props(admin, "/admin/content?q=" + content_slug)["items"][0]
        content_id = stored["id"]
        content["id"] = str(content_id)
        editor = props(admin, "/admin/content/" + str(content_id) + "/edit")["item"]
        check([item["id"] for item in editor["tags"]] == [tag_id], "editor lost assigned tags")
        check(props(public, "/tags/" + slug)["items"] == [], "tag archive exposed a draft")
        content["status"] = "published"
        check(
            admin.request("/admin/content/save", "POST", content)[0] == 303,
            "publish tagged content item",
        )
        archive = props(public, "/tags/" + slug)
        check([item["id"] for item in archive["items"]] == [content_id], "tag archive is stale")
        detail = props(public, "/content/" + content_slug)["item"]
        check(detail["tags"][0]["name"] == name, "public content item lost tag labels")
        renamed = {**tag, "id": str(tag_id), "name": name + " revised", "slug": slug + "-revised"}
        check(admin.request("/admin/tags/save", "POST", renamed)[0] == 303, "rename assigned tag")
        check(public.request("/tags/" + slug)[0] == 404, "old tag slug remained cached")
        check(
            len(props(public, "/tags/" + renamed["slug"])["items"]) == 1, "tag rename lost content"
        )
        check(
            props(public, "/content/" + content_slug)["item"]["tags"][0]["name"] == renamed["name"],
            "tag rename left a stale detail label",
        )
        invalid_status, _, invalid_body = admin.request(
            "/admin/content/save", "POST", {**content, "tags": "99999999"}
        )
        check(
            invalid_status == 422,
            "missing tag assignment returned " + str(invalid_status) + ": " + invalid_body[:300],
        )
        remove_status, remove_headers, remove_body = admin.request(
            "/admin/tags/" + str(tag_id) + "/delete", "POST", {}
        )
        check(
            remove_status == 303,
            "delete assigned tag returned "
            + str(remove_status)
            + ": "
            + str(remove_headers)
            + " "
            + remove_body[:1000],
        )
        check(
            props(public, "/content/" + content_slug)["item"]["tags"] == [],
            "deleted tag remained on content",
        )
        deleted_status, _, deleted_body = public.request("/tags/" + renamed["slug"])
        check(
            deleted_status == 404,
            "deleted tag archive returned " + str(deleted_status) + ": " + deleted_body[:300],
        )
    finally:
        if content_id is not None:
            admin.request("/admin/content/" + str(content_id) + "/delete", "POST", {})
        admin.request("/admin/tags/" + str(tag_id) + "/delete", "POST", {})
    print(
        "PASS CMS tags: guarded CRUD, assignment, draft privacy, public archives and rename/delete cache coherence",
        flush=True,
    )


if __name__ == "__main__":
    run()
