#!/usr/bin/env python3
"""Rotate the password for a Cisco ISE internal user via the ERS API.

Looks up the target internal user by name, generates a strong random
password matching ISE complexity rules, and PUTs the update via
/ers/config/internaluser/{id}.

Reads three env vars:
    ISE_HOST            ISE host or host:port (e.g. 10.100.4.10 or 127.0.0.1:50443)
    ISE_ADMIN_USER      ISE admin with the External RESTful Services Admin role
    ISE_ADMIN_PASSWORD  password for that admin

The admin user MUST have the ERS Admin role specifically. The default
Super Admin role does NOT include ERS access; you grant it explicitly
in ISE under Administration > System > Admin Access > Administrators >
Admin Users.

Cisco ISE ERS API reference:
    https://developer.cisco.com/docs/identity-services-engine/latest/

Usage:
    python rotate_ise_internal_user.py --target svc-automation
"""

from __future__ import annotations

import argparse
import logging
import os
import secrets
import string
import sys
import urllib3
from typing import Final

import requests
from requests.auth import HTTPBasicAuth

# ISE ERS listens on TCP 9060 by default. The ERS_PORT can be overridden
# via the ISE_HOST env var (passing host:port).
ERS_DEFAULT_PORT: Final[int] = 9060
HTTP_TIMEOUT_SECONDS: Final[int] = 30

# ISE password complexity (default policy): 6+ chars, mix of upper/lower/digit
# at minimum. Most production ISE deployments raise the requirement and add
# special chars. We default to a 32-char password that satisfies any
# reasonable policy.
_UPPER: Final[str] = string.ascii_uppercase
_LOWER: Final[str] = string.ascii_lowercase
_DIGITS: Final[str] = string.digits
_SPECIAL: Final[str] = "!@#%^*()-_=+[]{}:,.?/"

logger = logging.getLogger("rotate-ise-internal-user")


def generate_password(length: int) -> str:
    """Build a random password meeting ISE's character-class requirements.

    ISE enforces at least one upper, one lower, one digit, and (in most
    deployments) one special character. We seed the password with one of
    each and shuffle.
    """
    if length < 6:
        raise ValueError("Password length must be at least 6 (ISE minimum).")

    rng = secrets.SystemRandom()
    pool = _UPPER + _LOWER + _DIGITS + _SPECIAL

    chars = [
        rng.choice(_UPPER),
        rng.choice(_LOWER),
        rng.choice(_DIGITS),
        rng.choice(_SPECIAL),
    ]
    chars.extend(rng.choice(pool) for _ in range(length - len(chars)))
    rng.shuffle(chars)
    return "".join(chars)


def build_session(admin_user: str, admin_password: str, verify_tls: bool) -> requests.Session:
    """Construct a requests.Session preloaded with auth and ERS headers.

    ISE's ERS API requires both Accept and Content-Type headers set to
    application/json. Some ISE versions also reject calls that lack the
    correct combination.
    """
    session = requests.Session()
    session.auth = HTTPBasicAuth(admin_user, admin_password)
    session.headers.update({
        "Accept": "application/json",
        "Content-Type": "application/json",
    })
    session.verify = verify_tls
    return session


def base_url(host: str) -> str:
    """Build the ERS base URL. Accepts host or host:port."""
    if ":" in host:
        return f"https://{host}/ers/config"
    return f"https://{host}:{ERS_DEFAULT_PORT}/ers/config"


def lookup_internal_user(session: requests.Session, host: str, name: str) -> dict:
    """Find an ISE internal user by name. Returns the user object dict.

    ISE's ERS exposes a "by name" lookup at
    /ers/config/internaluser/name/{name}. The response includes the user's
    id, which is what we need for the subsequent PUT.
    """
    url = f"{base_url(host)}/internaluser/name/{name}"
    logger.debug("GET %s", url)
    response = session.get(url, timeout=HTTP_TIMEOUT_SECONDS)

    if response.status_code == 404:
        raise RuntimeError(f"Internal user '{name}' not found in ISE.")
    if response.status_code == 401:
        raise RuntimeError(
            "401 from ISE. The admin user lacks the ERS Admin role, or the "
            "credentials are wrong."
        )
    response.raise_for_status()

    return response.json()["InternalUser"]


def update_password(
    session: requests.Session,
    host: str,
    user: dict,
    new_password: str,
    also_enable_password: bool,
) -> None:
    """PUT a password update to ISE.

    ISE requires the entire InternalUser object on PUT, but only fields
    we want to change need real values - the rest are echoed back from
    the GET. We send id, name, password, and (optionally) enablePassword.
    """
    user_id = user["id"]
    url = f"{base_url(host)}/internaluser/{user_id}"

    body: dict = {
        "InternalUser": {
            "id": user_id,
            "name": user["name"],
            "password": new_password,
        }
    }
    if also_enable_password:
        body["InternalUser"]["enablePassword"] = new_password

    logger.debug("PUT %s", url)
    response = session.put(url, json=body, timeout=HTTP_TIMEOUT_SECONDS)

    if response.status_code in (200, 204):
        return

    # ISE error responses include a structured ERSResponse object.
    try:
        err = response.json().get("ERSResponse", {})
        message = err.get("messages", [{}])[0].get("title", response.text)
    except (ValueError, IndexError, AttributeError):
        message = response.text
    raise RuntimeError(f"ISE update failed ({response.status_code}): {message}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rotate a Cisco ISE internal user password via ERS API.",
    )
    parser.add_argument(
        "--target",
        required=True,
        metavar="USERNAME",
        help="Username of the ISE internal user to rotate, e.g. svc-automation",
    )
    parser.add_argument(
        "--length",
        type=int,
        default=32,
        help="Generated password length (default: 32, minimum: 6).",
    )
    parser.add_argument(
        "--also-enable-password",
        action="store_true",
        help="Also set the optional enablePassword field to the same value.",
    )
    parser.add_argument(
        "--insecure",
        action="store_true",
        help=(
            "Skip TLS verification. ISE ships with a self-signed cert; use "
            "this flag for demo/lab use only. In production, install a "
            "trusted cert chain on ISE."
        ),
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Verbose logging to stderr.",
    )
    return parser.parse_args()


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        logger.error("Environment variable %s is not set.", name)
        sys.exit(1)
    return value


def main() -> int:
    args = parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        stream=sys.stderr,
    )

    if args.insecure:
        # Suppress the "Unverified HTTPS request" warning when --insecure is
        # used intentionally. We don't suppress it globally so other code
        # paths still warn correctly.
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    host = require_env("ISE_HOST")
    admin_user = require_env("ISE_ADMIN_USER")
    admin_password = require_env("ISE_ADMIN_PASSWORD")

    try:
        new_password = generate_password(args.length)
    except ValueError as exc:
        logger.error("%s", exc)
        return 1

    session = build_session(admin_user, admin_password, verify_tls=not args.insecure)

    try:
        logger.debug("Looking up internal user %s", args.target)
        user = lookup_internal_user(session, host, args.target)

        logger.debug("Updating password for user id %s", user["id"])
        update_password(
            session=session,
            host=host,
            user=user,
            new_password=new_password,
            also_enable_password=args.also_enable_password,
        )
    except RuntimeError as exc:
        logger.error("%s", exc)
        return 1
    except requests.RequestException as exc:
        logger.error("Network error talking to ISE: %s", exc)
        return 1

    print(f"Password rotated for ISE internal user {args.target}")
    print(f"New password: {new_password}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
