"""Verify the native handler validation lifecycle and explicit admin guard."""

import hashlib
import json
import os
import secrets
import time

from cms_content import props
from e2e import Client, check
from fixture_store import FixtureStore


def run():
    with FixtureStore.from_environment() as fixtures:
        verify(fixtures)


def verify(fixtures):
    email = os.environ["TEST_ADMIN_EMAIL"]
    password = os.environ["TEST_ADMIN_PASSWORD"]
    key = hashlib.sha256(b"login:127.0.0.1").hexdigest()
    filters = [("key", "=", key)]
    fixtures.delete("login_attempts", filters)
    probe = Client()
    probe.request("/admin/login")
    for invalid in (
        {"password": password},
        {"email": "invalid-email", "password": password},
        {"email": email, "password": ""},
        {"email": email, "password": [password]},
        {"email": 123, "password": password},
        {"email": email, "password": "x" * 73},
    ):
        response = probe.request(
            "/admin/login",
            "POST",
            raw=json.dumps(invalid).encode(),
            content_type="application/json",
        )
        check(response[0] == 422, "Invalid credentials did not stop at native validation")
    check(
        fixtures.count("login_attempts", filters) == 0,
        "The execute method ran for an invalid request",
    )
    owner = Client()
    owner.request("/admin/login")
    check(
        owner.request("/admin/login", "POST", {"email": email.upper(), "password": password})[0]
        == 303,
        "Native admin guard login or email normalization failed",
    )
    suffix = secrets.token_hex(5)
    member_email = f"native-login-{suffix}@example.test"
    member_password = secrets.token_urlsafe(36)
    member = {
        "name": "Native login fixture",
        "email": member_email,
        "password": member_password,
        "role": "writer",
        "active": "0",
    }
    identifier = None
    try:
        check(
            owner.request("/admin/team/save", "POST", member)[0] == 303,
            "Create inactive login fixture",
        )
        identifier = fixtures.rows("admins", ["id"], [("email", "=", member_email)], limit=1)[0][
            "id"
        ]
        check(
            probe.request(
                "/admin/login", "POST", {"email": member_email, "password": member_password}
            )[0]
            == 401,
            "An inactive account authenticated",
        )
        check(probe.request("/admin")[0] == 303, "Inactive login created an authenticated session")
        check(
            owner.request(
                "/admin/team/save",
                "POST",
                {**member, "id": identifier, "password": "", "active": "1"},
            )[0]
            == 303,
            "Activate login fixture",
        )
        fixtures.delete("login_attempts", filters)
        for _ in range(5):
            check(
                probe.request(
                    "/admin/login",
                    "POST",
                    {"email": member_email, "password": "incorrect-password"},
                )[0]
                == 401,
                "Incorrect password did not return 401",
            )
        check(
            probe.request(
                "/admin/login", "POST", {"email": member_email, "password": member_password}
            )[0]
            == 429,
            "The failed-login limit was removed",
        )
        fixtures.update("login_attempts", {"expires_at": time.time() - 1}, filters)
        response = probe.request(
            "/admin/login",
            "POST",
            {
                "email": member_email.upper(),
                "password": member_password,
                "role": "owner",
                "active": "0",
            },
        )
        check(
            response[0] == 303,
            "Long passwords, extra-field whitelisting or expired-limit recovery failed",
        )
        check(
            props(probe, "/admin")["auth"]["admin"]["role"] == "writer",
            "Unexpected fields changed the authenticated role",
        )
        check(probe.request("/admin/settings")[0] == 403, "Admin guard granted extra privileges")
        check(
            fixtures.count("login_attempts", filters) == 0,
            "Successful login did not clear failed attempts",
        )
        probe.request("/admin/logout", "POST", {})
    finally:
        if identifier is not None:
            fixtures.delete("admins", [("id", "=", identifier)])
        fixtures.delete("login_attempts", filters)
        owner.request("/admin/logout", "POST", {})
    print(
        "PASS Native login: validation before execute, only credentials, admin guard, long passwords, inactive accounts, role isolation and failed-attempt expiry",
        flush=True,
    )


if __name__ == "__main__":
    run()
