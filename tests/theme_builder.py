"""Exercise real visual themes: drafts, publishing, cache, conflicts and media ownership."""

import copy
import json
import os
from pathlib import Path
import secrets
import subprocess

from cms_content import HEADERS, props
from cms_management import login
from e2e import Client, check
from fixture_store import FixtureStore
from validation import post_json

ROOT = Path(__file__).resolve().parents[1]


def run():
    subprocess.run(["node", str(ROOT / "tests/theme_builder_model.mjs")], cwd=ROOT, check=True)
    owner = login(os.environ["TEST_ADMIN_EMAIL"], os.environ["TEST_ADMIN_PASSWORD"])
    public = Client()
    with FixtureStore.from_environment() as fixtures:
        verify(owner, public, fixtures)
    print(
        "PASS Theme builder: create, all templates, draft isolation, publish/activate, server rendering, validation, version conflicts, CSRF, permissions and media retention",
        flush=True,
    )


def line_break_variants(design, ending):
    """Copies of `design` in which one validated value ends in `ending`."""
    first_block = design["templates"]["Home"][0]["blocks"][0]
    block_values = {
        "id": f"{first_block['id']}{ending}",
        "slot": f"site.footer{ending}",
        "source": f"page.related{ending}",
        "styles": {"desktop": {"normal": {f"behavior{ending}": "none"}}},
    }
    variants = []
    for key, value in block_values.items():
        variant = copy.deepcopy(design)
        variant["templates"]["Home"][0]["blocks"][0][key] = value
        variants.append((f"block {key}", variant))
    font = copy.deepcopy(design)
    font["tokens"]["font"] = f"Arial{ending}"
    variants.append(("font stack", font))
    template = copy.deepcopy(design)
    template["templates"][f"Landing{ending}"] = []
    variants.append(("template name", template))
    return variants


def verify(owner, public, fixtures):
    previous = props(public, "/")["theme"]["id"]
    name = f"Visual theme {secrets.token_hex(5)}"
    status, headers, body = owner.request(
        "/admin/themes/create", "POST", {"name": name, "starter": "content"}
    )
    check(status == 303, f"Theme creation failed: {body[:200]}")
    editor_url = headers["location"]
    studio = props(owner, editor_url)["studio"]
    identifier = studio["id"]
    base = f"/admin/themes/{identifier}"
    design = studio["document"]
    check(
        studio["version"] == 1 and studio["publishedVersion"] == 0,
        "Theme did not start as an unpublished draft",
    )
    check(
        props(public, "/")["theme"]["id"] == previous, "Creating a theme changed the live website"
    )
    check(
        owner.request(f"{base}/enable", "POST", {})[0] == 422,
        "An unpublished theme could be activated",
    )
    check(
        any(
            package["id"] == identifier and package["designed"]
            for package in props(owner, "/admin/themes")["packages"]
        ),
        "Created theme is not editable from its card",
    )

    def save(document, version, action="save", csrf=True):
        return (
            post_json(
                owner,
                editor_url,
                {
                    "name": name,
                    "design": json.dumps(document),
                    "version": str(version),
                    "action": action,
                },
            )
            if csrf
            else owner.request(
                editor_url,
                "POST",
                {
                    "name": name,
                    "design": json.dumps(document),
                    "version": str(version),
                    "action": action,
                },
                csrf=False,
            )
        )

    image_id = None
    try:
        for template in ["Home", "ContentIndex", "ContentDetail", "Page", "About", "NotFound"]:
            frame = props(owner, f"{studio['frameUrl']}&template={template}")
            check(
                frame["theme"]["studioSession"] == studio["session"]
                and frame["templateFallback"] == template,
                f"Wrong studio template context: {template}",
            )
            check(frame["theme"]["design"]["schema"] == 2, "Design missing from iframe")
            check(
                "extensions" in frame and "pluginNavigation" in frame,
                "Studio iframe lost public plugin slots or navigation",
            )
        check(save(design, 1, csrf=False)[0] == 419, "Theme builder bypassed CSRF")
        invalid = copy.deepcopy(design)
        invalid["tokens"]["accent"] = "url(unsafe)"
        check(save(invalid, 1)[0] == 422, "Invalid design color accepted")
        invalid = copy.deepcopy(design)
        invalid["templates"]["Home"][0]["blocks"][0]["id"] = design["header"][0]["id"]
        check(save(invalid, 1)[0] == 422, "Duplicate design IDs accepted")
        invalid = copy.deepcopy(design)
        invalid["templates"]["Home"][0]["blocks"][0]["href"] = "javascript:alert(1)"
        check(save(invalid, 1)[0] == 422, "Executable design link accepted")
        invalid["templates"]["Home"][0]["blocks"][0]["href"] = "/safe"
        invalid["templates"]["Home"][0]["blocks"][0]["image"] = "https://example.com/photo.jpg"
        check(save(invalid, 1)[0] == 422, "External blog image accepted")
        # `$` also matches before a final line break; design JSON is not trimmed.
        for ending in ["\n", "\r\n", "\u2028"]:
            for field, invalid in line_break_variants(design, ending):
                check(
                    save(invalid, 1)[0] == 422,
                    f"A design {field} ending in {ending!r} was accepted",
                )
            check(
                save(design, 1, f"save{ending}")[0] == 422,
                f"A design action ending in {ending!r} was accepted",
            )
        check(
            post_json(
                owner, editor_url, {"name": [], "design": "{}", "version": "1", "action": "save"}
            )[0]
            == 422,
            "Native validation accepted a non-string name",
        )
        check(
            props(owner, editor_url)["studio"]["version"] == 1,
            "Rejected design changed its version",
        )

        uploaded = owner.upload_image(
            "/admin/media/upload",
            (ROOT / "public/images/coast.jpg").read_bytes(),
            "image/jpeg",
            (1000, 750),
        )
        check(uploaded[0] == 201, "Theme image upload failed")
        image = json.loads(uploaded[2])
        image_id = image["id"]
        image_block = {
            "id": "studio-image",
            "type": "image",
            "text": "",
            "href": "",
            "image": image["url"],
            "alt": "Coast",
            "level": 1,
        }
        design["templates"]["Home"][0]["blocks"].append(image_block)
        design["templates"]["Home"][0]["blocks"][0]["text"] = "Published design heading"
        for ending in ["\n", "\u2028"]:
            invalid = copy.deepcopy(design)
            invalid["templates"]["Home"][0]["blocks"][-1]["image"] = f"{image['url']}{ending}"
            check(save(invalid, 1)[0] == 422, f"A design image ending in {ending!r} was accepted")
        check(save(design, 1)[0] == 200, "Theme draft save failed")
        check(
            props(public, "/")["theme"]["id"] == previous, "Saving a draft changed the active theme"
        )
        check(
            owner.request(f"/admin/media/{str(image_id)}/trash", "POST", {})[0] == 422,
            "An image referenced by a theme draft was deleted",
        )
        check(save(design, 1)[0] == 422, "An outdated editor overwrote a newer design")
        check(save(design, 2, "publish")[0] == 200, "Publishing theme failed")
        check(
            owner.request(f"{base}/enable", "POST", {})[0] == 303,
            "Published theme activation failed",
        )
        active = props(public, "/")["theme"]
        check(
            active["id"] == identifier
            and active["design"]["templates"]["Home"][0]["blocks"][0]["text"]
            == "Published design heading",
            "Published theme cache is stale",
        )
        html = public.request("/")[2]
        check(
            'data-layout="builder"' in html
            and "Published design heading" in html
            and image["url"] in html,
            "Visual theme did not render as server HTML",
        )
        draft = copy.deepcopy(design)
        draft["templates"]["Home"][0]["blocks"] = draft["templates"]["Home"][0]["blocks"][:-1]
        draft["templates"]["Home"][0]["blocks"][0]["text"] = "Draft only heading"
        check(save(draft, 3)[0] == 200, "Active theme draft save failed")
        public_design = props(public, "/")["theme"]["design"]
        check(
            public_design["templates"]["Home"][0]["blocks"][0]["text"]
            == "Published design heading",
            "An active theme leaked an unpublished draft",
        )
        check(
            owner.request(f"/admin/media/{str(image_id)}/trash", "POST", {})[0] == 422,
            "A published design image lost protection after editing the draft",
        )
        check(save(draft, 4, "publish")[0] == 200, "Republishing active theme failed")
        check(
            "Draft only heading" in public.request("/")[2],
            "Republishing did not invalidate the rendered design",
        )
        check(
            owner.delete_media(image_id)[0] == 303,
            "Unreferenced design image remained locked",
        )
        image_id = None
        check(public.request(editor_url)[0] == 303, "Public access to theme builder was accepted")
        check(
            public.request(studio["frameUrl"])[0] == 303,
            "Public access to theme draft iframe was accepted",
        )
        email = f"studio-editor-{secrets.token_hex(5)}@example.test"
        password = secrets.token_urlsafe(20)
        check(
            owner.request(
                "/admin/team/save",
                "POST",
                {
                    "name": "Studio editor",
                    "email": email,
                    "password": password,
                    "role": "editor",
                    "active": "1",
                },
            )[0]
            == 303,
            "Permission test member creation failed",
        )
        member = login(email, password)
        check(
            member.request(editor_url)[0] == 403
            and member.request("/admin/themes/create")[0] == 403,
            "Editor could manage themes",
        )
        check(
            post_json(
                member,
                editor_url,
                {"name": name, "design": json.dumps(design), "version": "5", "action": "save"},
            )[0]
            == 403,
            "Editor could write visual designs",
        )
        fixtures.delete("admins", [("email", "=", email)])
    finally:
        owner.request(f"/admin/themes/{previous}/enable", "POST", {})
        status, _, body = owner.request(f"{base}/uninstall", "POST", {})
        check(status == 303, f"Visual theme uninstall failed: {body[:150]}")
        check(
            fixtures.count("theme_designs", [("id", "=", identifier)]) == 0,
            "Uninstall left a design record",
        )
        check(
            fixtures.count("media_dependencies", [("owner", "=", identifier)]) == 0,
            "Uninstall left theme media dependencies",
        )
        if image_id is not None:
            owner.delete_media(image_id)


if __name__ == "__main__":
    run()
