"""Verify the CMS's native framework API integrations through real HTTP and ORM fixtures."""

import base64
import json
import os
import subprocess

from cms_content import HEADERS, props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from validation import post_json


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    with FixtureStore.from_environment() as fixtures:
        check(fixtures.call("native_api_checks"), "Native facade checks failed")
        entities = ["content_types", "roles", "navigation_regions"]
        before = {entity: fixtures.count(entity) for entity in entities}
        for path, values in [
            ("/admin/content-types/create", {"definition": []}),
            ("/admin/content-types/create", {"definition": "x" * 60001}),
            ("/admin/roles/create", {"key": "test_role", "name": [], "capabilities": "[]"}),
            ("/admin/roles/create", {"key": "test_role", "name": "Test", "capabilities": []}),
            ("/admin/navigation/regions/save", {"key": "header", "name": [], "max_links": "12"}),
            (
                "/admin/navigation/regions/save",
                {"key": "header", "name": "Header", "max_links": "12x"},
            ),
        ]:
            status, _, body = post_json(owner, path, values)
            check(
                status == 422,
                f"{path} accepted malformed fields: {str(status)} {body[:100]}",
            )
        check(
            before == {entity: fixtures.count(entity) for entity in entities},
            "Invalid definition requests changed stored data",
        )
        status, headers, _ = post_json(owner, "/admin/roles/create", {"name": []}, HEADERS)
        check(status == 303, "Native validation did not redirect back with flashed errors")
        check(
            props(owner, headers["location"])["errors"].get("role"),
            "Native flash did not reach the role editor",
        )
        check(
            not props(owner, headers["location"])["errors"],
            "Native flash was retained after consumption",
        )

        editor = props(owner, "/admin/pages/new")
        media_rules = editor["mediaRules"]
        draft_key = editor["draftKey"]
        try:
            status, _, body = post_json(
                owner,
                "/admin/pages/working-copy?title=Unvalidated-query-title",
                {"draft_key": draft_key, "draft_version": "1", "content": "A working copy."},
            )
            check(status == 200, f"Native working-copy map conversion failed: {body[:100]}")
            working = props(owner, f"/admin/pages/new?draft={draft_key}")["workingCopy"]
            check(
                working["data"].get("title") is None
                and working["data"]["content"] == "A working copy.",
                "Working-copy conversion admitted an unvalidated query value",
            )
        finally:
            owner.request("/admin/pages/0/discard-working", "POST", {"draft_key": draft_key})

        content = base64.b64decode("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
        status, _, body = owner.upload_image("/admin/media/upload", content, "image/gif", (1, 1))
        check(status == 201, f"GIF upload failed: {body[:100]}")
        image = json.loads(body)
        try:
            script = """
import { readFileSync } from 'node:fs';
const { rules, url } = JSON.parse(readFileSync(0, 'utf8'));
const pattern = new RegExp(rules.imagePattern);
if (!pattern.test(url) || pattern.test(url + '?unmanaged=1') || pattern.test('https://example.com/image.gif')) {
  throw new Error('The managed-image pattern is not valid in JavaScript.');
}
"""
            subprocess.run(
                ["node", "--input-type=module", "-e", script],
                input=json.dumps({"rules": media_rules, "url": image["url"]}),
                text=True,
                check=True,
            )
            status, headers, payload = Client().request(image["url"], binary=True)
            check(
                status == 200 and headers["content-type"] == "image/gif" and payload == content,
                "Native Storage MIME handling changed GIF responses",
            )
        finally:
            owner.request(f"/admin/media/{str(image['id'])}/delete", "POST", {})
    owner.request("/admin/logout", "POST", {})
    print(
        "PASS Native CMS APIs: facade conversion/flash, remaining handlers, input-source isolation and Storage MIME responses",
        flush=True,
    )


if __name__ == "__main__":
    run()
