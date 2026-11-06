"""Restore a full backup into a new site and compare every table and stored file with the source."""

import io
import json
import os
from pathlib import Path
import tempfile
import zipfile

from e2e import Client, check
from fixture_store import FixtureStore
from installation import SetupClient, SetupServer
from site_backup import FULL, RESTORE, export, upload_backup

# Rows that only matter to the running site; backups leave these tables out.
TRANSIENT = [
    "login_attempts",
    "package_uploads",
    "image_uploads",
    "theme_ai_connections",
    "scheduled_backup_files",
]
# Backups leave out the markers that vouch for bundled plugin files, so a restored site
# installs its own copies of these plugins on first start.
BUNDLED = {"plugin-rss", "plugin-newsletter", "plugin-site-backup"}
REINSTALLED = ["activity_logs", "cms_packages", "package_hooks"]
# Archive entries that describe the backup rather than hold a stored file.
METADATA = ("database/", "content/", "backup.", "content.index.json")
SHOWN_ROWS = 2000


def digests(store):
    return {table["name"]: table for table in store.call("table_digests", skip=TRANSIENT)}


def rows(store, table, columns):
    values = store.call("table_rows", table=table, limit=SHOWN_ROWS)
    check(len(values) < SHOWN_ROWS, f"{table} has too many rows to compare one by one")
    return [dict(zip(columns, json.loads(value))) for value in values]


def compare_reinstalled(source, restored, columns):
    """
    Bundled plugins keep their settings, state and hooks; only their copies are new.
    Returns the restored folder of each bundled plugin, keyed by its folder in the backup.
    """
    expected = {row["id"]: row for row in rows(source, "cms_packages", columns["cms_packages"])}
    actual = {row["id"]: row for row in rows(restored, "cms_packages", columns["cms_packages"])}
    check(sorted(actual) == sorted(expected), f"Restored packages differ: {sorted(actual)}")
    for identifier, package in expected.items():
        changed = sorted(key for key, value in package.items() if actual[identifier][key] != value)
        allowed = ["directory", "updated_at"] if identifier in BUNDLED else []
        check(set(changed) <= set(allowed), f"The restored package {identifier} changed {changed}")

    expected_hooks = rows(source, "package_hooks", columns["package_hooks"])
    actual_hooks = rows(restored, "package_hooks", columns["package_hooks"])
    events = lambda hooks: sorted((hook["package_id"], hook["event"]) for hook in hooks)
    check(events(actual_hooks) == events(expected_hooks), "Restored package hooks differ")
    kept = lambda hooks: [hook for hook in hooks if hook["package_id"] not in BUNDLED]
    check(kept(actual_hooks) == kept(expected_hooks), "Restored plugin hooks changed")

    expected_logs = rows(source, "activity_logs", columns["activity_logs"])
    actual_logs = rows(restored, "activity_logs", columns["activity_logs"])
    missing = [entry for entry in expected_logs if entry not in actual_logs]
    check(not missing, f"The restore lost activity entries: {missing[:3]}")
    added = [entry for entry in actual_logs if entry not in expected_logs]
    names = {expected[identifier]["name"] for identifier in BUNDLED if identifier in expected}
    check(
        sorted(entry["label"] for entry in added) == sorted(names)
        and all(
            entry["action"] == "updated"
            and entry["entity"] == "plugin"
            and entry["actor"] == "System"
            for entry in added
        ),
        f"The restore recorded unexpected activity: {added[:3]}",
    )
    return {
        f"extensions/installed/{expected[identifier]['directory']}/": (
            f"extensions/installed/{actual[identifier]['directory']}/"
        )
        for identifier in BUNDLED
        if identifier in expected
    }


def describe(source, restored, table):
    expected = set(source.call("table_rows", table=table, limit=SHOWN_ROWS))
    actual = set(restored.call("table_rows", table=table, limit=SHOWN_ROWS))
    missing = sorted(expected - actual)[:3]
    added = sorted(actual - expected)[:3]
    return f"missing {missing}, unexpected {added}"


def compare_tables(source, restored, expected):
    actual = digests(restored)
    check(
        sorted(actual) == sorted(expected),
        f"Restored tables differ: missing {sorted(set(expected) - set(actual))}, "
        f"unexpected {sorted(set(actual) - set(expected))}",
    )
    problems = []
    for name, table in expected.items():
        restored_table = actual[name]
        if restored_table["columns"] != table["columns"]:
            problems.append(f"{name} columns are {restored_table['columns']}")
        elif name not in REINSTALLED and restored_table["digest"] != table["digest"]:
            problems.append(
                f"{name} has {restored_table['rows']} rows, expected {table['rows']}; "
                f"{describe(source, restored, name)}"
            )
    check(not problems, "Restored tables differ from the source:\n" + "\n".join(problems))
    return compare_reinstalled(
        source, restored, {name: expected[name]["columns"] for name in REINSTALLED}
    )


def compare_files(archive, source_storage, restored_storage, media, moved):
    with zipfile.ZipFile(io.BytesIO(archive)) as entries:
        stored = [
            entry.filename
            for entry in entries.infolist()
            if not entry.is_dir() and not entry.filename.startswith(METADATA)
        ]
        missing_media = sorted({f"media/{filename}" for filename in media} - set(stored))
        check(not missing_media, f"The backup left out media files: {missing_media[:3]}")
        for path in stored:
            content = entries.read(path)
            check(
                (source_storage / path).read_bytes() == content,
                f"The backup copy of {path} differs from the site's file",
            )
            folder = next((old for old in moved if path.startswith(old)), None)
            target = path if folder is None else moved[folder] + path[len(folder) :]
            restored = restored_storage / target
            check(
                restored.is_file() and restored.read_bytes() == content,
                f"The restored {target} differs from the backup's {path}",
            )
    for old, new in moved.items():
        check(
            old == new or not (restored_storage / old).exists(),
            f"The restored site kept the replaced plugin folder {old}",
        )
    return len(stored)


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
    verify_round_trip(owner)


def verify_round_trip(owner):
    with FixtureStore.from_environment() as source:
        expected = digests(source)
        check(
            expected["content_items"]["rows"] > 0 and expected["media_assets"]["rows"] > 0,
            "The source site has no content or media to compare",
        )
        media = [row["filename"] for row in source.scan("media_assets", ["id", "filename"])]
        archive = export(owner, FULL)
        check(digests(source) == expected, "Exporting a backup changed the site's data")
        with tempfile.TemporaryDirectory(prefix="haxepress-backup-roundtrip-") as name:
            work = Path(name)
            server = SetupServer(work, None)
            try:
                client = SetupClient(server.url)
                check(
                    client.request("/admin/install", data=True)[0] == 200, "Installer unavailable"
                )
                status, _, result = upload_backup(client, RESTORE, archive)
                check(status == 200 and result["restored"], f"Backup restore failed: {result}")
                with FixtureStore(work) as restored:
                    moved = compare_tables(source, restored, expected)
                files = compare_files(
                    archive, source.work / "storage", work / "storage", media, moved
                )
            finally:
                server.close()
    total = sum(table["rows"] for table in expected.values())
    print(
        f"PASS Backup round trip: {len(expected)} tables, {total} rows and {files} files match the source after restore",
        flush=True,
    )


if __name__ == "__main__":
    run()
