"""Exercise verified site backups and restore them into a separate installer."""

import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import secrets
import struct
import subprocess
import tempfile
import time
import zipfile

from cms_content import props
from cms_management import login
from e2e import BASE, Client, check
from fixture_store import FixtureStore, TEST_BINARY
from installation import SetupClient, SetupServer

BACKUPS = "/admin/backups"
SCHEDULES = f"{BACKUPS}/schedules"
BACKUP_PLUGIN = "/admin/plugins/plugin-site-backup"
# A restored site installs the bundled plugins when the backup leaves plugins out.
BUNDLED_PLUGINS = ["rss", "newsletter", "cloudflare", "view-count", "site-backup"]
CMS_VERSION = json.loads((Path(__file__).resolve().parents[1] / "cms.json").read_text())["version"]
VERIFY = f"{BACKUPS}/verify"
RESTORE = "/admin/install/restore"
RECOVER = f"{RESTORE}?skip_damaged_content=1"
VERIFIED = f"{RESTORE}?use_verified_database=1"
FULL = {"content": True, "themes": True, "plugins": True}
IMAGE = (Path(__file__).parent / "fixtures/media/logo-transparent.png").read_bytes()


def backup_header(content):
    check(
        content.startswith(b"HXPRESS\0\x02\x01"), "The .hxpress header has the wrong format or type"
    )
    encrypted = content[10] == 1
    version_size = content[11]
    version = content[12 : 12 + version_size].decode()
    check(version == CMS_VERSION, "The public backup header does not declare its CMS release")
    size = struct.unpack_from(">I", content, 12 + version_size)[0]
    return encrypted, size, 16 + version_size + (32 if encrypted else 0)


def plain_backup(payload, version=CMS_VERSION):
    version = version.encode()
    return (
        b"HXPRESS\0\x02\x01\x00"
        + bytes([len(version)])
        + version
        + struct.pack(">I", len(payload))
        + payload
    )


def prepare(client, sections):
    if isinstance(client, SetupClient):
        status, headers, body = client.request(BACKUPS, sections)
        return status, headers, json.dumps(body)
    return client.request(
        BACKUPS,
        "POST",
        raw=json.dumps(sections).encode(),
        content_type="application/json",
    )


def post_json(client, path, values, *, csrf=True):
    if isinstance(client, SetupClient):
        return client.request(path, values, csrf=csrf)
    status, headers, body = client.request(
        path,
        "POST",
        raw=json.dumps(values).encode(),
        content_type="application/json",
        csrf=csrf,
    )
    if "application/json" in headers.get("content-type", ""):
        body = json.loads(body)
    return status, headers, body


def send_part(client, path, data):
    if isinstance(client, SetupClient):
        return client.request(path, raw=data)
    return client.request(path, "POST", raw=data)


def upload_backup(client, action, content, *, csrf=True):
    uploads = f"{action.split('?', 1)[0]}/uploads"
    status, headers, ticket = post_json(client, uploads, {"size": len(content)}, csrf=csrf)
    if status != 201:
        return status, headers, ticket
    chunk_size = ticket["chunkSize"]
    check(0 < chunk_size <= 1024 * 1024, "The upload returned an unbounded chunk size")
    for index, offset in enumerate(range(0, len(content), chunk_size)):
        status, _, _ = send_part(
            client, f"{uploads}/{ticket['id']}/{index}", content[offset : offset + chunk_size]
        )
        check(status == 200, f"Backup chunk {index} returned {status}")
    return post_json(client, action, {"upload": ticket["id"]})


def verify_wire_limits():
    token = "a" * 32
    path = f"{VERIFY}/uploads/{token}/0"
    oversized = 1024 * 1024 + 1
    reject_oversized(
        BASE.hostname,
        BASE.port,
        [(path, oversized, False), (path, oversized, True), (VERIFY, 4097, False)],
    )
    verify_http2_limits(path, oversized)


def reject_oversized(host, port, targets):
    """Each POST declares a body above its route's limit and is refused before it is sent."""
    for target, length, chunked in targets:
        connection = http.client.HTTPConnection(host, port, timeout=5)
        try:
            connection.putrequest("POST", target)
            if chunked:
                connection.putheader("Transfer-Encoding", "chunked")
            else:
                connection.putheader("Content-Length", str(length))
            connection.endheaders()
            if chunked:
                connection.send(f"{length:x}\r\n".encode())
            check(connection.getresponse().status == 413, "The wire body limit was not enforced")
        finally:
            connection.close()


def verify_http2_limits(path, oversized):
    probe = """
const http2 = require('node:http2');
const [origin, path, size] = process.argv.slice(1);
const client = http2.connect(origin);
const timeout = setTimeout(() => client.destroy(new Error('No early 413 response')), 5000);

async function rejectOversized(declared) {
  return new Promise((resolve, reject) => {
    const headers = { ':method': 'POST', ':path': path };
    if (declared) headers['content-length'] = size;
    const request = client.request(headers, { endStream: false });
    request.once('error', reject);
    request.once('response', (response) => {
      if (response[':status'] !== 413) {
        reject(new Error('Unexpected response status ' + response[':status']));
      } else {
        resolve();
      }
    });
    request.resume();
    if (!declared) request.end(Buffer.alloc(Number(size)));
  });
}

(async () => {
  try {
    await rejectOversized(true);
    await rejectOversized(false);
  } finally {
    clearTimeout(timeout);
    client.destroy();
  }
})().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
"""
    result = subprocess.run(
        ["node", "-e", probe, f"http://{BASE.netloc}", path, str(oversized)],
        capture_output=True,
        text=True,
        timeout=12,
    )
    check(result.returncode == 0, f"HTTP/2 backup limit failed: {result.stderr[:220]}")


def verify_staging(owner, content):
    uploads = f"{VERIFY}/uploads"
    status, _, ticket = post_json(owner, uploads, {"size": len(content)})
    check(status == 201, "Could not start a chunked upload")
    key, chunk_size = ticket["id"], ticket["chunkSize"]
    check(len(content) > chunk_size, "The backup fixture did not span several chunks")
    staged = f"{uploads}/{key}"
    status, _, body = post_json(owner, VERIFY, {"upload": key})
    check(status == 422 and "incomplete" in body["error"], "An incomplete ZIP was accepted")
    second = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    props(second, BACKUPS)
    check(send_part(second, f"{staged}/0", b"x")[0] == 404, "An upload crossed sessions")
    check(send_part(owner, f"{staged}/0", content[:chunk_size])[0] == 200, "First chunk failed")
    check(send_part(owner, f"{staged}/0", b"x")[0] == 422, "A short chunk was accepted")
    for index, offset in enumerate(range(chunk_size, len(content), chunk_size), start=1):
        status, _, _ = send_part(owner, f"{staged}/{index}", content[offset : offset + chunk_size])
        check(status == 200, "Remaining backup chunk failed")
    status, _, body = post_json(owner, VERIFY, {"upload": key})
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        md5 = archive.read("backup.md5").decode()
    check(status == 200 and body == {"verified": True, "md5": md5}, "The assembled ZIP changed")
    check(post_json(owner, VERIFY, {"upload": key})[0] == 422, "An upload was consumed twice")

    status, _, ticket = post_json(owner, uploads, {"size": 1})
    check(status == 201, "Could not start a second upload")
    staged = f"{uploads}/{ticket['id']}"
    check(owner.request(staged, "DELETE", {})[0] == 200, "Could not cancel a backup upload")
    check(send_part(owner, f"{staged}/0", b"x")[0] == 404, "A cancelled upload remained active")


def verify_schedules(owner, denied, fixtures):
    daily = {
        "name": "Daily content",
        "content": True,
        "themes": False,
        "plugins": False,
        "intervalSeconds": 86400,
        "encrypted": False,
        "retain": 2,
        "enabled": True,
    }
    weekly = {
        **daily,
        **FULL,
        "name": "Weekly full backup",
        "intervalSeconds": 7 * 86400,
        "encrypted": True,
        "retain": 1,
    }
    check(post_json(denied, SCHEDULES, daily)[0] == 403, "A settings role could schedule backups")
    check(
        post_json(owner, SCHEDULES, daily, csrf=False)[0] == 419, "Schedule creation bypassed CSRF"
    )
    core = fixtures.rows("scheduled_jobs", ["plugin_id"], [("id", "=", "core:temporary-files")])
    check(core == [{"plugin_id": None}], "A core job was assigned to a plugin")
    keys = []

    def files(key):
        status, _, body = owner.request(f"{SCHEDULES}/{key}/files")
        check(status == 200, f"Scheduled backups could not be listed: {body[:250]}")
        return json.loads(body)["archives"]

    def due(key):
        fixtures.update(
            "scheduled_jobs",
            {"next_epoch": int(time.time() * 1000) - 1000},
            [("job_key", "=", key)],
        )

    def wait_for_file(key, previous):
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            archives = files(key)
            if archives and archives[0]["id"] != previous:
                return archives[0]
            state = next(item for item in props(owner, BACKUPS)["schedules"] if item["id"] == key)
            check(not state["lastError"], f"Scheduled backup failed: {state['lastError']}")
            time.sleep(0.2)
        raise AssertionError("The scheduled backup did not run")

    try:
        for policy in (daily, weekly):
            status, _, result = post_json(owner, SCHEDULES, policy)
            check(status == 200 and result["saved"], f"Schedule save failed: {result}")
            keys.append(result["id"])
        daily_id, weekly_id = keys
        due(daily_id)
        first = wait_for_file(daily_id, None)
        due(daily_id)
        second = wait_for_file(daily_id, first["id"])
        check(len(files(daily_id)) == 2, "The daily schedule did not retain two backups")
        due(weekly_id)
        full = wait_for_file(weekly_id, None)
        check(full["encrypted"] and not second["encrypted"], "Encryption was shared across rules")
        check(full["cmsVersion"] == CMS_VERSION, "Scheduled backup lost its CMS version")
        status, _, content = owner.request(second["download"], binary=True)
        check(
            status == 200 and not backup_header(content)[0],
            "The saved backup could not be downloaded",
        )
        with zipfile.ZipFile(io.BytesIO(content)) as archive:
            manifest = json.loads(archive.read("backup.json"))
            check(not manifest["sections"]["plugins"], "The daily backup included plugins")
            check(
                not archive.read("database/scheduled_backup_files.rows"),
                "The backup contained other backups",
            )
        check(
            owner.request(second["download"], binary=True)[2] == content,
            "A scheduled download was consumed",
        )
        check(
            Client().request(second["download"])[0] == 303, "A public visitor downloaded an archive"
        )
        check(denied.request(second["download"])[0] == 403, "A settings role downloaded an archive")
        check(
            denied.request(f"{SCHEDULES}/{daily_id}/files")[0] == 403,
            "A settings role listed archives",
        )
        status, _, _ = post_json(owner, f"{SCHEDULES}/{daily_id}", {**daily, "retain": 1})
        check(status == 200 and len(files(daily_id)) == 1, "Lowering retention did not prune")
        check(owner.request(first["download"])[0] == 404, "A pruned archive remained downloadable")
        check(len(files(weekly_id)) == 1, "Daily retention removed the weekly archive")

        check(
            owner.request(f"{BACKUP_PLUGIN}/uninstall", "POST", {})[0] == 422,
            "The bundled backup plugin could be removed",
        )
        check(
            owner.request(f"{BACKUP_PLUGIN}/disable", "POST", {})[0] == 303,
            "Could not deactivate backups",
        )
        check(owner.request(BACKUPS)[0] == 404, "Deactivated backups retained the admin route")
        due(daily_id)
        time.sleep(3.5)
        condition = [("id", "=", second["id"])]
        check(
            fixtures.count("scheduled_backup_files", condition) == 1,
            "A disabled plugin ran retention",
        )
        check(
            owner.request(f"{BACKUP_PLUGIN}/enable", "POST", {})[0] == 303,
            "Could not reactivate backups",
        )
        wait_for_file(daily_id, second["id"])
    finally:
        if owner.request(BACKUPS)[0] == 404:
            owner.request(f"{BACKUP_PLUGIN}/enable", "POST", {})
        for key in keys:
            owner.request(f"{SCHEDULES}/{key}", "DELETE", {})
    print(
        "PASS Backup schedules: independent policy, retention, authorization and plugin lifecycle",
        flush=True,
    )


def verify_permissions(owner, fixtures):
    page = props(owner, BACKUPS)
    status, _, html = owner.request(BACKUPS)
    check(
        status == 200 and "<h1>Backup / Restore</h1>" in html and 'id="backup-to-restore"' in html,
        "Backup / Restore did not render as server HTML",
    )
    groups = {
        group["label"]: [link["href"] for link in group["links"]]
        for group in page["adminNavigation"]
    }
    check(
        BACKUPS in groups.get("Extensions", []), "Backup / Restore is not listed under Extensions"
    )
    links = [link for group in page["adminNavigation"] for link in group["links"]]
    check(
        all(BACKUPS not in link["activePaths"] for link in links),
        "Another menu entry is current on the backups page",
    )
    listing = owner.request("/admin/plugins")[2]
    check(
        f'href="{BACKUPS}"' in listing, "The Backups card's Settings button does not open its page"
    )
    check("backup" not in props(owner, "/admin/settings"), "The old Settings card was retained")
    status, _, body = owner.request("/admin/roles/capabilities?q=backups")
    check(
        status == 200 and any(choice["key"] == "backups" for choice in json.loads(body)["choices"]),
        "Backup permission was not registered",
    )
    check(Client().request(BACKUPS)[0] == 303, "The backup page requires an admin session")
    key = f"backups_{secrets.token_hex(5)}"
    email = f"{key}@example.test"
    password = secrets.token_urlsafe(18)
    role = {"key": key, "name": "Backup access test", "enabled": "1"}
    try:
        check(
            owner.request("/admin/roles/create", "POST", {**role, "capabilities": '["settings"]'})[
                0
            ]
            == 303,
            "Could not create a settings-only role",
        )
        check(
            owner.request(
                "/admin/team/save",
                "POST",
                {
                    "name": "Backup delegate",
                    "email": email,
                    "password": password,
                    "role": key,
                    "active": "1",
                },
            )[0]
            == 303,
            "Could not create a backup delegate",
        )
        member = login(email, password)
        page = props(member, "/admin/settings")
        links = [link for group in page["adminNavigation"] for link in group["links"]]
        check(all(link["href"] != BACKUPS for link in links), "Settings exposed the backup menu")
        check(member.request(BACKUPS)[0] == 403, "Settings opened the backup page")
        check(prepare(member, FULL)[0] == 403, "Settings allowed backup export")
        check(
            post_json(member, VERIFY, {"upload": "a" * 32})[0] == 403, "Settings allowed rehearsal"
        )
        check(
            post_json(member, f"{VERIFY}/uploads", {"size": 1})[0] == 403,
            "Settings allowed staging a backup",
        )
        verify_schedules(owner, member, fixtures)

        def grant(capability):
            status, _, _ = owner.request(
                f"/admin/roles/{key}/save",
                "POST",
                {**role, "capabilities": json.dumps([capability])},
            )
            check(status == 303, "Could not change the delegated role")

        grant("extensions")
        check(
            f'href="{BACKUPS}"' not in member.request("/admin/plugins")[2],
            "The Backups card offered its page without the backup permission",
        )
        grant("backups")
        check(member.request("/admin/settings")[0] == 403, "Backup grant also opened Settings")
        props(member, BACKUPS)
        status, _, body = prepare(member, {"content": False, "themes": True, "plugins": False})
        check(status == 200, f"Delegated export failed: {body[:250]}")
        link = json.loads(body)["download"]
        check(owner.request(link)[0] == 404, "A download token worked for a different admin")
        grant("settings")
        check(member.request(link)[0] == 403, "Revoked backup permission left a download active")
        grant("backups")
        check(member.request(link, binary=True)[0] == 200, "Delegate could not download its ZIP")
    finally:
        fixtures.delete("admins", [("email", "=", email)])
        owner.request(f"/admin/roles/{key}/delete", "POST", {})


def download_backup(client, sections):
    status, headers, body = prepare(client, sections)
    check(status == 200, f"Could not verify the backup: {body[:350]}")
    check("content-disposition" not in headers, "Preparing a backup started a download")
    verified = json.loads(body)
    status, headers, content = client.request(verified["download"], binary=True)
    disposition = headers.get("content-disposition", "")
    check(
        status == 200 and "attachment" in disposition and ".hxpress" in disposition,
        "Verified backup download failed",
    )
    check(client.request(verified["download"])[0] == 404, "Backup download was not removed")
    return content, verified["md5"]


def export(client, sections):
    content, expected_md5 = download_backup(client, sections)
    encrypted, _, _ = backup_header(content)
    check(not encrypted, "A plaintext export was marked encrypted")
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        manifest = json.loads(archive.read("backup.json"))
        check(manifest["sections"] == sections, "Backup sections changed")
        check(manifest["version"] == 3, "Expected a portable backup")
        check(
            "database/schema.json" in archive.namelist()
            and "database/admins.rows" in archive.namelist()
            and "database.sqlite" not in archive.namelist(),
            "The ZIP does not contain the logical database format",
        )
        digest = hashlib.md5()
        core = hashlib.md5()
        for entry in archive.infolist():
            if entry.filename == "backup.md5":
                continue
            header = entry_header(entry.filename, entry.file_size)
            digest.update(header)
            in_core = (
                not entry.filename.startswith("content/") and entry.filename != "backup.core.md5"
            )
            if in_core:
                core.update(header)
            with archive.open(entry) as stream:
                for block in iter(lambda: stream.read(65536), b""):
                    digest.update(block)
                    if in_core:
                        core.update(block)
        check(
            archive.read("backup.md5").decode() == digest.hexdigest() == expected_md5,
            "ZIP checksum does not cover the backup entries",
        )
        check(
            archive.read("backup.core.md5").decode() == core.hexdigest(),
            "Independent core checksum changed",
        )
        if sections["content"]:
            for identifier in json.loads(archive.read("content.index.json")):
                path = f"content/{identifier}/content"
                record = archive.read(path)
                check(json.loads(record)["id"] == identifier, "Content item data differs")
                check(
                    archive.read(f"{path}.hash").decode() == hashlib.md5(record).hexdigest(),
                    "Content item checksum differs",
                )
        if not sections["plugins"]:
            check(
                "database/plugin_backup_probe.rows" not in archive.namelist(),
                "An excluded plugin table was included",
            )
    return content


def verify_encrypted_backup(owner, sections):
    content, md5 = download_backup(owner, {**sections, "encrypted": True})
    encrypted, length, header_size = backup_header(content)
    check(encrypted, "The backup header did not report encryption")
    frame = 64 * 1024
    count = (length + frame - 1) // frame
    check(
        count > 1 and len(content) == header_size + length + count * 16,
        "The encrypted backup did not use bounded authenticated frames",
    )
    check(not zipfile.is_zipfile(io.BytesIO(content)), "The encrypted file exposed the ZIP")
    status, _, result = upload_backup(owner, VERIFY, content)
    check(
        status == 200 and result == {"verified": True, "md5": md5},
        f"Encrypted backup rehearsal failed: {result}",
    )
    damaged = bytearray(content)
    damaged[header_size + frame + 16] ^= 1
    status, _, result = upload_backup(owner, VERIFY, bytes(damaged))
    check(
        status == 422 and "original APP_KEY" in result["error"],
        f"Tampered encrypted frame was accepted: {result}",
    )
    status, _, result = upload_backup(owner, VERIFY, content[:-1])
    check(
        status == 422 and "invalid size" in result["error"],
        "A truncated encrypted backup was accepted",
    )
    return content


def reject_wrong_key(content):
    with tempfile.TemporaryDirectory(prefix="haxepress-backup-wrong-key-") as name:
        work = Path(name)
        server = SetupServer(work, None)
        try:
            client = SetupClient(server.url)
            client.request("/admin/install", data=True)
            # The restore step belongs to the Backups plugin, which runs only while installing.
            reject_oversized(
                "127.0.0.1",
                server.port,
                [
                    (RESTORE, 4097, False),
                    (f"{RESTORE}/uploads/{'a' * 32}/0", 1024 * 1024 + 1, False),
                ],
            )
            environment = (work / ".env").read_bytes()
            status, _, result = upload_backup(client, RESTORE, content)
            check(
                status == 422 and "original APP_KEY" in result["error"],
                f"A different project key opened the backup: {result}",
            )
            check(
                (work / ".env").read_bytes() == environment
                and not list((work / "data").glob("restored-*.sqlite")),
                "A wrong-key restore modified the target installation",
            )
        finally:
            server.close()


def entry_header(name, size):
    return f"{len(name)}:{name}:{size}\n".encode()


def rewrite(content, changes, *, remove=(), add=(), rehash=False, rehash_core=False):
    output = io.BytesIO()
    digest = hashlib.md5()
    core = hashlib.md5()
    with (
        zipfile.ZipFile(io.BytesIO(content)) as source,
        zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as target,
    ):
        entries = [(name, source.read(name)) for name in source.namelist() if name not in remove]
        for name, original in [*entries, *add]:
            if (rehash and name == "backup.md5") or (rehash_core and name == "backup.core.md5"):
                continue
            data = changes.get(name, original)
            target.writestr(name, data)
            if rehash:
                digest.update(entry_header(name, len(data)))
                digest.update(data)
            if rehash_core and not name.startswith("content/"):
                core.update(entry_header(name, len(data)))
                core.update(data)
        if rehash_core:
            checksum = core.hexdigest().encode()
            target.writestr("backup.core.md5", checksum)
            digest.update(entry_header("backup.core.md5", len(checksum)))
            digest.update(checksum)
        if rehash:
            target.writestr("backup.md5", digest.hexdigest())
    return plain_backup(output.getvalue())


def damage_entries(content, identifiers):
    bad, missing = [f"content/{identifier}/content" for identifier in identifiers]
    damaged = bytearray(rewrite(content, {}, remove=(missing, f"{missing}.hash")))
    with zipfile.ZipFile(io.BytesIO(damaged)) as archive:
        offset = archive.getinfo(bad).header_offset
        filename_size, extra_size = struct.unpack_from("<HH", damaged, offset + 26)
    data_offset = offset + 30 + filename_size + extra_size
    damaged[data_offset] |= 0b110  # Reserved DEFLATE block type, with the ZIP index still intact.
    return bytes(damaged)


def orphaned_reference(content):
    name = "plugin_backup_probe"
    path = f"database/{name}.rows"
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        schema = json.loads(archive.read("database/schema.json"))
        table = next(table for table in schema if table["name"] == name)
        columns = [column["name"] for column in table["columns"]]
        data = archive.read(path)
    size = struct.unpack_from(">I", data)[0]
    record = json.loads(data[4 : size + 4])
    record[columns.index("content_id")] = "2147483647"
    row = json.dumps(record).encode()
    invalid = struct.pack(">I", len(row)) + row + data[size + 4 :]
    return rewrite(content, {path: invalid}, rehash=True, rehash_core=True)


def reject_corruption(client, content, damaged):
    checksum_only = rewrite(content, {"backup.md5": b"0" * 32})
    for path, payload, message in [
        (RESTORE, checksum_only, "MD5"),
        (RECOVER, checksum_only, "MD5"),
        (RESTORE, damaged, "MD5"),
        (RECOVER, rewrite(content, {"database/admins.rows": b"damaged"}), "core MD5"),
    ]:
        status, _, result = upload_backup(client, path, payload)
        check(status == 422 and message in result["error"], f"Damaged ZIP accepted: {result}")
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        identifier = json.loads(archive.read("content.index.json"))[0]
    hash_path = f"content/{identifier}/content.hash"
    status, _, result = upload_backup(
        client, RESTORE, rewrite(content, {hash_path: b"0" * 32}, rehash=True)
    )
    check(status == 422 and "damaged or missing" in result["error"], "Item hash was ignored")


def restore(
    content,
    expected_items,
    expected_plugins,
    theme_id,
    image,
    *,
    damaged=None,
    skipped=(),
    survivor=None,
    mysql=None,
    app_key=None,
):
    with tempfile.TemporaryDirectory(prefix="haxepress-backup-restore-") as name:
        work = Path(name)
        server = SetupServer(work, None, app_key=app_key)
        try:
            client = SetupClient(server.url)
            check(client.request("/admin/install", data=True)[0] == 200, "Installer unavailable")
            path = RECOVER if skipped else RESTORE
            if mysql:
                status, _, result = client.request("/admin/install/database", mysql)
                check(status == 200 and result["verified"], f"MySQL verification failed: {result}")
                status, _, result = upload_backup(client, VERIFIED, orphaned_reference(content))
                check(
                    status == 422 and "invalid foreign key" in result["error"],
                    f"Invalid MySQL restore outcome: {status} {result}",
                )
                status, _, result = client.request("/admin/install/database", mysql)
                check(status == 200 and result["verified"], "A failed restore left MySQL tables")
                path = VERIFIED
            if damaged is not None:
                check(
                    upload_backup(client, RESTORE, content, csrf=False)[0] == 419,
                    "Restore bypassed CSRF",
                )
                reject_corruption(client, content, damaged)
                check(
                    not list((work / "data").glob("restored-*.sqlite")),
                    "Failed restore published a database",
                )
            status, _, result = upload_backup(client, path, content)
            check(status == 200 and result["restored"], f"Backup restore failed: {result}")
            check(result["skippedContent"] == list(skipped), "Skipped items were not reported")
            check(client.request("/admin/install", data=True)[0] == 404, "Restore left setup open")
            client.request("/admin/login", data=True)
            check(
                client.request(
                    "/admin/login",
                    {
                        "email": os.environ["TEST_ADMIN_EMAIL"],
                        "password": os.environ["TEST_ADMIN_PASSWORD"],
                    },
                )[0]
                == 303,
                "The restored owner could not sign in",
            )
            with FixtureStore(work) as restored:
                check(restored.count("items") == expected_items, "Restored content count differs")
                if survivor:
                    check(
                        restored.rows(
                            "items", list(survivor), [("id", "=", survivor["id"])], limit=1
                        )
                        == [survivor],
                        "The intact content item changed",
                    )
                    check(
                        restored.call("backup_probe", operation="verify", contentId=survivor["id"]),
                        "A plugin's composite keys, large integers or binary values changed",
                    )
                if skipped:
                    check(
                        restored.count("content_revisions", [("document_id", "=", skipped[0])]) == 0
                        and restored.count("menu_links", [("content_id", "=", skipped[0])]) == 0
                        and restored.count(
                            "settings", [("key", "=", "home_page"), ("value", "=", "0")]
                        )
                        == 1,
                        "A skipped item left stale content references",
                    )
                check(
                    restored.count("cms_packages", [("kind", "=", "plugin")])
                    == (expected_plugins or len(BUNDLED_PLUGINS)),
                    "Restored plugins differ",
                )
                check(
                    restored.count("theme_designs", [("id", "=", theme_id)]) == 1
                    and restored.count("theme_assets", [("theme_id", "=", theme_id)]) == 1,
                    "A visual theme lost its design or image metadata",
                )
                check(
                    restored.count("subscribers", [("email", "=", "backup@example.test")])
                    == (1 if expected_plugins else 0),
                    "The restored subscriber data differs from the selected plugin section",
                )
            check(
                (work / "storage/themes" / theme_id / image).read_bytes() == IMAGE,
                "The restored theme image changed",
            )
            check(
                client.request("/rss.xml")[0] == 200,
                "Plugin routes differ after restore",
            )
            if mysql:
                check("DB_DRIVER='mysql'" in (work / ".env").read_text(), "Wrong target driver")
                return export(client, FULL)
        finally:
            server.close()


def verify_mysql(content, item_count, plugin_count, theme_id, image, survivor):
    name = f"haxepress_backup_{secrets.token_hex(5)}"
    port = os.environ["TEST_MYSQL_PORT"]
    work = Path(os.environ["TEST_MYSQL_WORK"])
    classpath = f"{TEST_BINARY}{os.pathsep}{TEST_BINARY.parent / 'lib/*'}"
    command = ["java", "-cp", classpath, "fixtures.MysqlSetupFixture", port, name]
    subprocess.run(command, cwd=work, check=True, capture_output=True)
    try:
        exported = restore(
            content,
            item_count,
            plugin_count,
            theme_id,
            image,
            survivor=survivor,
            mysql={
                "driver": "mysql",
                "host": "127.0.0.1",
                "port": port,
                "database": name,
                "username": "root",
                "password": "",
            },
        )
        restore(exported, item_count, plugin_count, theme_id, image, survivor=survivor)
    finally:
        subprocess.run(command + ["drop"], cwd=work, check=True, capture_output=True)
    print(
        "PASS SQLite to MySQL and back with plugin rows, checksums and failed-restore cleanup",
        flush=True,
    )


def run():
    owner = Client()
    owner.request("/admin/login")
    check(
        owner.request(
            "/admin/login",
            "POST",
            {
                "email": os.environ["TEST_ADMIN_EMAIL"],
                "password": os.environ["TEST_ADMIN_PASSWORD"],
            },
        )[0]
        == 303,
        "Owner login failed",
    )
    with FixtureStore.from_environment() as source:
        verify_permissions(owner, source)
    verify_wire_limits()
    status, headers, _ = owner.request(
        "/admin/themes/create", "POST", {"name": "Backup visual theme", "starter": "blank"}
    )
    check(status == 303, "Could not create a visual theme for the backup")
    theme_id = headers["location"].split("/")[-2]
    theme = f"/admin/themes/{theme_id}"
    subscriber = [("email", "=", "backup@example.test")]
    try:
        status, _, body = owner.upload_image(f"{theme}/assets", IMAGE, "image/png", (120, 40))
        check(status == 201, f"Theme image upload failed: {body[:150]}")
        image = json.loads(body)["filename"]
        status, _, _ = Client().request(
            "/subscribe", "POST", {"email": "backup@example.test"}, csrf=False
        )
        check(status == 200, "Could not create plugin data for the backup")
        with FixtureStore.from_environment() as source:
            item_count = source.count("items")
            plugin_count = source.count("cms_packages", [("kind", "=", "plugin")])
            package = [("id", "=", "theme-fieldnotes")]
            manifest = source.rows("cms_packages", ["id", "manifest"], package, limit=1)[0][
                "manifest"
            ]
            inconsistent = json.loads(manifest)
            inconsistent["version"] = "99.0.0"
            try:
                source.update("cms_packages", {"manifest": json.dumps(inconsistent)}, package)
                status, _, body = prepare(owner, FULL)
                check(
                    status == 422
                    and "does not match its files" in body
                    and "download" not in json.loads(body),
                    f"A failed restore rehearsal exposed a backup: {status} {body[:350]}",
                )
            finally:
                source.update("cms_packages", {"manifest": manifest}, package)
            first, second, survivor = source.rows(
                "items", ["id", "title", "content", "image_alt"], limit=3
            )
            original = {"content": survivor["content"], "image_alt": survivor["image_alt"]}
            survivor["content"] = "İçerik\n" * 11000
            survivor["image_alt"] = "İ" * 500
            survivor_filter = [("id", "=", survivor["id"])]
            skipped = [first["id"], second["id"]]
            owner_link = [("label", "=", "Backup recovery link")]
            revision = [("document_id", "=", first["id"]), ("version", "=", 99)]
            home = [("key", "=", "home_page")]
            home_mode = [("key", "=", "home_mode")]
            settings = {
                key: source.rows("settings", ["key", "value"], conditions, limit=1)[0]["value"]
                for key, conditions in [("home_page", home), ("home_mode", home_mode)]
            }
            try:
                source.call("backup_probe", operation="create", contentId=survivor["id"])
                source.update(
                    "items",
                    {"content": survivor["content"], "image_alt": survivor["image_alt"]},
                    survivor_filter,
                )
                source.create(
                    "content_revisions",
                    [
                        {
                            "document_id": first["id"],
                            "version": 99,
                            "title": first["title"],
                            "snapshot": "{}",
                            "author_id": 1,
                            "created_at": "2025-02-03 04:05:06",
                        }
                    ],
                )
                source.create(
                    "menu_links",
                    [
                        {
                            "location": "header",
                            "label": "Backup recovery link",
                            "url": "",
                            "position": 90,
                            "content_id": first["id"],
                            "created_at": "2025-02-03 04:05:06",
                            "updated_at": "2025-02-03 04:05:06",
                        }
                    ],
                )
                source.update("settings", {"value": str(first["id"])}, home)
                source.update("settings", {"value": "page"}, home_mode)
                archive = export(owner, FULL)
            finally:
                source.call("backup_probe", operation="drop")
                source.update("items", original, survivor_filter)
                source.delete("menu_links", owner_link)
                source.delete("content_revisions", revision)
                source.update("settings", {"value": settings["home_page"]}, home)
                source.update("settings", {"value": settings["home_mode"]}, home_mode)
            check(
                source.count("items") == item_count, "Restore rehearsal changed the live database"
            )
            check(
                upload_backup(owner, VERIFY, archive, csrf=False)[0] == 419,
                "Restore rehearsal bypassed CSRF",
            )
            verify_staging(owner, archive)
            status, _, _ = upload_backup(owner, VERIFY, rewrite(archive, {"backup.md5": b"0" * 32}))
            check(status == 422, "Admin restore rehearsal accepted a damaged ZIP")
            live = source.rows("items", list(original), survivor_filter, limit=1)
            check(live == [original], "Admin restore rehearsal altered the installed site")
            sections = {"content": False, "themes": True, "plugins": False}
            selected = export(owner, sections)
            encrypted = verify_encrypted_backup(owner, sections)
            app_key = next(
                line.split("=", 1)[1]
                for line in (source.work / ".env").read_text().splitlines()
                if line.startswith("APP_KEY=")
            )
        reject_wrong_key(encrypted)
        restore(encrypted, 0, 0, theme_id, image, app_key=app_key)
        damaged = damage_entries(archive, skipped)
        restore(
            archive, item_count, plugin_count, theme_id, image, damaged=damaged, survivor=survivor
        )
        restore(
            damaged,
            item_count - len(skipped),
            plugin_count,
            theme_id,
            image,
            skipped=skipped,
            survivor=survivor,
        )
        restore(selected, 0, 0, theme_id, image)
        _, _, payload_offset = backup_header(selected)
        check(
            upload_backup(owner, VERIFY, selected[payload_offset:])[0] == 422,
            "A raw ZIP was accepted",
        )
        wrong_version = plain_backup(selected[payload_offset:], version="0.0.0")
        status, _, result = upload_backup(owner, VERIFY, wrong_version)
        check(
            status == 422 and "Restore this backup with HaxePress 0.0.0" in result["error"],
            "A backup from a different CMS version was accepted",
        )
        if os.environ.get("TEST_MYSQL_PORT"):
            verify_mysql(archive, item_count, plugin_count, theme_id, image, survivor)
    finally:
        with FixtureStore.from_environment() as source:
            source.delete("subscribers", subscriber)
        owner.request(f"{theme}/uninstall", "POST", {})
    print(
        "PASS Site backups: authenticated encryption, key matching, bounded uploads and selective recovery",
        flush=True,
    )


if __name__ == "__main__":
    run()
