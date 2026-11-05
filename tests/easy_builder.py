"""Verify beginner starters and the publish-and-activate website action."""

import copy
import json
import os
from pathlib import Path
import secrets
import subprocess

from cms_content import props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from validation import post_json

ROOT = Path(__file__).resolve().parents[1]


def run():
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    base = props(owner, "/admin/themes/create")["baseDocument"]
    generated = subprocess.run(
        ["node", str(ROOT / "tests/easy_builder_fixtures.mjs")],
        input=json.dumps(base),
        text=True,
        capture_output=True,
        check=True,
        cwd=ROOT,
    )
    fixtures = json.loads(generated.stdout)
    with FixtureStore.from_environment() as store:
        verify(owner, public, store, fixtures)
    print(
        "PASS Easy builder: four validated starters, ready sections, protected drafts, publish-and-activate, optimistic saves, persistence and CSRF",
        flush=True,
    )


def verify(owner, public, store, fixtures):
    previous = props(public, "/")["theme"]["id"]
    created = []
    suffix = secrets.token_hex(5)
    try:
        for kind, document in fixtures["documents"].items():
            if kind == "business":
                document["templates"]["About"].extend(fixtures["sections"])
            status, headers, body = post_json(
                owner,
                "/admin/themes/create",
                {
                    "name": "Easy " + kind + " " + suffix,
                    "starter": "blank",
                    "design": json.dumps(document),
                },
            )
            check(
                status == 303, "Starter did not pass native validation: " + kind + ": " + body[:200]
            )
            url = headers["location"]
            studio = props(owner, url)["studio"]
            created.append((url, studio))
            check(
                studio["version"] == 1
                and studio["publishedVersion"] == 0
                and not studio["enabled"],
                "A starter was published before the user chose to publish",
            )
            check(
                studio["document"]["tokens"]["accent"] == document["tokens"]["accent"],
                "Starter palette was lost",
            )
            check(
                props(public, "/")["theme"]["id"] == previous,
                "Creating a website design changed the live theme",
            )
        count_before = store.count("theme_designs")
        status, _, _ = post_json(
            owner,
            "/admin/themes/create",
            {"name": "Invalid " + suffix, "starter": "blank", "design": "{}"},
        )
        check(
            status == 422 and store.count("theme_designs") == count_before,
            "Invalid starter data created a partial theme",
        )
        url, studio = created[0]
        document = copy.deepcopy(studio["document"])
        first = document["templates"]["Home"][0]["blocks"][0]["children"][0]
        first["text"] = "A website built simply"
        payload = {
            "name": studio["name"],
            "design": json.dumps(document),
            "version": "1",
            "action": "launch",
        }
        check(
            owner.request(url, "POST", payload, csrf=False)[0] == 419,
            "Website publication bypassed CSRF",
        )
        status, _, body = post_json(owner, url, payload)
        check(status == 200, "One-step publication failed: " + body[:200])
        result = json.loads(body)
        check(
            result["active"] is True and result["version"] == result["publishedVersion"] == 2,
            "Launch did not publish and activate together",
        )
        live = props(public, "/")
        check(live["theme"]["id"] == studio["id"], "Launch left another theme active")
        check(
            "A website built simply" in public.request("/")[2], "Published starter did not render"
        )
        first["text"] = "A saved draft change"
        payload.update(design=json.dumps(document), version="2", action="save")
        status, _, body = post_json(owner, url, payload)
        check(status == 200 and json.loads(body)["version"] == 3, "Draft save failed")
        check(
            "A website built simply" in public.request("/")[2],
            "Saving a draft changed the published website",
        )
        check(
            props(owner, url)["studio"]["document"]["templates"]["Home"][0]["blocks"][0][
                "children"
            ][0]["text"]
            == "A saved draft change",
            "Saved draft did not survive a reload",
        )
        payload.update(version="3", action="launch")
        check(
            post_json(owner, url, payload)[0] == 200,
            "Publishing changes on the active design failed",
        )
        check(
            "A saved draft change" in public.request("/")[2],
            "Published changes did not reach the website",
        )
        payload["version"] = "2"
        check(
            post_json(owner, url, payload)[0] == 422,
            "An outdated editor overwrote the current website",
        )
    finally:
        owner.request("/admin/themes/" + previous + "/enable", "POST", {})
        for _, studio in created:
            owner.request("/admin/themes/" + studio["id"] + "/uninstall", "POST", {})


if __name__ == "__main__":
    run()
