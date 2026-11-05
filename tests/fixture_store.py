"""Prepare and inspect isolated test data through the application's JVM ORM models."""

from contextlib import contextmanager
import json
import os
from pathlib import Path
import selectors
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
TEST_BINARY = ROOT / "Export/tests/hxwell.jar"
CONTENT_COLUMNS = [
    "id",
    "title",
    "slug",
    "excerpt",
    "content",
    "category",
    "image",
    "image_alt",
    "status",
    "content_type",
    "version",
    "author_id",
    "seo_title",
    "seo_description",
    "scheduled_epoch",
    "previous_status",
    "featured",
    "reading_minutes",
    "published_at",
    "created_at",
    "updated_at",
]


class FixtureStore:
    def __init__(self, work):
        self.work = Path(work)
        self.guard_path = self.work / "query-guard.json"
        self.buffer = b""
        self.log = (self.work / "fixtures.log").open("ab")
        classpath = str(TEST_BINARY) + os.pathsep + str(TEST_BINARY.parent / "lib/*")
        self.process = subprocess.Popen(
            [
                "java",
                "--enable-native-access=ALL-UNNAMED",
                "-cp",
                classpath,
                "fixtures.FixtureProcess",
            ],
            cwd=self.work,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.log,
        )
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        try:
            assert self.receive() == "ready", "Fixture process did not become ready"
        except Exception:
            self.close()
            raise

    @classmethod
    def from_environment(cls):
        return cls(Path(os.environ["TEST_DB_PATH"]).parent.parent)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def close(self):
        if self.process.stdin:
            self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.selector.close()
        self.process.stdout.close()
        self.log.close()

    def receive(self):
        deadline = time.monotonic() + 30
        while True:
            if b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                if not line.startswith(b"{"):
                    continue
                result = json.loads(line)
                if not result["ok"]:
                    raise RuntimeError(result["error"])
                return result["value"]
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not self.selector.select(remaining):
                raise RuntimeError(
                    "Fixture process timed out; see " + str(self.work / "fixtures.log")
                )
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError("Fixture process exited; see " + str(self.work / "fixtures.log"))
            self.buffer += chunk

    def call(self, action, entity=None, **parameters):
        command = {"action": action, "entity": entity, **parameters}
        self.process.stdin.write(json.dumps(command).encode() + b"\n")
        self.process.stdin.flush()
        return self.receive()

    @staticmethod
    def filters(conditions):
        return [
            {"column": column, "op": operator, "value": value}
            for column, operator, value in conditions
        ]

    def create(self, entity, records):
        identifiers = []
        for offset in range(0, len(records), 100):
            batch = records[offset : offset + 100]
            identifiers.extend(self.call("create", entity, records=batch))
        return identifiers

    def rows(self, entity, columns, conditions=(), after=None, limit=100):
        return self.call(
            "rows",
            entity,
            columns=columns,
            filters=self.filters(conditions),
            after=after,
            limit=limit,
        )

    def scan(self, entity, columns, conditions=()):
        primary = (
            "path"
            if entity == "content_type_paths"
            else (
                "key"
                if entity
                in {
                    "settings",
                    "editor_drafts",
                    "package_uploads",
                    "content_types",
                    "roles",
                    "capabilities",
                    "media_dependency_sources",
                    "login_attempts",
                }
                else "id"
            )
        )
        assert primary in columns, "A fixture scan requires its cursor column"
        after = None
        while True:
            batch = self.rows(entity, columns, conditions, after=after)
            if not batch:
                return
            yield from batch
            after = batch[-1][primary]

    def count(self, entity, conditions=()):
        return self.call("count", entity, filters=self.filters(conditions))

    def update(self, entity, values, conditions):
        return self.call("update", entity, values=values, filters=self.filters(conditions))

    def delete(self, entity, conditions):
        return self.call("delete", entity, filters=self.filters(conditions))

    @contextmanager
    def guard(self, **policy):
        previous = self.guard_path.read_bytes() if self.guard_path.exists() else None
        temporary = self.guard_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(policy))
        temporary.replace(self.guard_path)
        try:
            yield
        finally:
            if previous is None:
                self.guard_path.unlink(missing_ok=True)
            else:
                temporary.write_bytes(previous)
                temporary.replace(self.guard_path)
