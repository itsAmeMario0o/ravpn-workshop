#!/usr/bin/env python3
"""Rotate the password for an Entra ID (Azure AD) service account.

Generates a strong random password, acquires a Microsoft Graph access token
via the client credentials flow, and calls Microsoft Graph to set the new
password on the specified user. Prints the new password to stdout exactly
once - capture it from output and store it in your secret manager.

Reads three env vars for app registration credentials:
    ENTRA_TENANT_ID
    ENTRA_CLIENT_ID
    ENTRA_CLIENT_SECRET

The app registration must have the Microsoft Graph application permission
User.ReadWrite.All with admin consent granted.

Microsoft Graph reference:
    https://learn.microsoft.com/graph/api/user-update

Usage:
    python rotate_entra_password.py --user svc-automation@rooez.com
"""

from __future__ import annotations

import argparse
import logging
import os
import secrets
import string
import sys
from typing import Final

import msal
import requests

GRAPH_BASE: Final[str] = "https://graph.microsoft.com/v1.0"
GRAPH_SCOPE: Final[list[str]] = ["https://graph.microsoft.com/.default"]
HTTP_TIMEOUT_SECONDS: Final[int] = 30

# Character classes for the password generator. The "special" set deliberately
# avoids characters that often cause friction in shells, URLs, and JSON
# (' " \ ` & ; < > $).
_UPPER: Final[str] = string.ascii_uppercase
_LOWER: Final[str] = string.ascii_lowercase
_DIGITS: Final[str] = string.digits
_SPECIAL: Final[str] = "!@#%^*()-_=+[]{}:,.?/"

logger = logging.getLogger("rotate-entra-password")


def generate_password(length: int) -> str:
    """Build a random password with at least one of each character class.

    Uses secrets.SystemRandom for cryptographic-quality randomness.
    Guarantees at least one upper, one lower, one digit, and one special.
    """
    if length < 12:
        raise ValueError("Password length must be at least 12.")

    rng = secrets.SystemRandom()
    pool = _UPPER + _LOWER + _DIGITS + _SPECIAL

    # Seed with one of each class so complexity rules are always satisfied.
    chars = [
        rng.choice(_UPPER),
        rng.choice(_LOWER),
        rng.choice(_DIGITS),
        rng.choice(_SPECIAL),
    ]
    chars.extend(rng.choice(pool) for _ in range(length - len(chars)))

    # Shuffle so the seeded chars are not always at the start.
    rng.shuffle(chars)
    return "".join(chars)


def get_graph_token(tenant_id: str, client_id: str, client_secret: str) -> str:
    """Acquire a Microsoft Graph access token via client credentials.

    Returns the bearer token string. Raises RuntimeError on auth failure.

    https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow
    """
    authority = f"https://login.microsoftonline.com/{tenant_id}"
    app = msal.ConfidentialClientApplication(
        client_id=client_id,
        authority=authority,
        client_credential=client_secret,
    )

    result = app.acquire_token_for_client(scopes=GRAPH_SCOPE)
    if "access_token" not in result:
        # MSAL puts the failure detail in error/error_description.
        msg = result.get("error_description") or result.get("error") or "unknown error"
        raise RuntimeError(f"Failed to acquire Graph token: {msg}")
    return str(result["access_token"])


def set_user_password(
    token: str,
    upn: str,
    new_password: str,
    force_change_at_next_signin: bool,
) -> None:
    """Set the password on the target Entra user via Microsoft Graph.

    Microsoft Graph returns 204 No Content on success - no body to parse.
    Raises RuntimeError with a clear message on common failure codes.
    """
    url = f"{GRAPH_BASE}/users/{upn}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    body = {
        "passwordProfile": {
            "password": new_password,
            "forceChangePasswordNextSignIn": force_change_at_next_signin,
        }
    }

    logger.debug("PATCH %s", url)
    response = requests.patch(url, headers=headers, json=body, timeout=HTTP_TIMEOUT_SECONDS)

    if response.status_code == 204:
        return
    if response.status_code == 404:
        raise RuntimeError(f"User '{upn}' not found in this tenant.")
    if response.status_code == 403:
        raise RuntimeError(
            "Forbidden. Confirm the app registration has User.ReadWrite.All "
            "with admin consent granted."
        )

    # Anything else: surface what Graph said.
    try:
        detail = response.json().get("error", {}).get("message", response.text)
    except ValueError:
        detail = response.text
    raise RuntimeError(f"Graph API error {response.status_code}: {detail}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rotate an Entra ID service account password via Microsoft Graph.",
    )
    parser.add_argument(
        "--user",
        required=True,
        metavar="UPN",
        help="User principal name of the service account, e.g. svc-automation@rooez.com",
    )
    parser.add_argument(
        "--length",
        type=int,
        default=32,
        help="Generated password length (default: 32, minimum: 12).",
    )
    parser.add_argument(
        "--force-change",
        action="store_true",
        help=(
            "Set forceChangePasswordNextSignIn=true. Do not use for service "
            "accounts; locks them out at next sign-in."
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

    tenant_id = require_env("ENTRA_TENANT_ID")
    client_id = require_env("ENTRA_CLIENT_ID")
    client_secret = require_env("ENTRA_CLIENT_SECRET")

    try:
        new_password = generate_password(args.length)
    except ValueError as exc:
        logger.error("%s", exc)
        return 1

    try:
        logger.debug("Acquiring Graph access token")
        token = get_graph_token(tenant_id, client_id, client_secret)

        logger.debug("Setting new password on %s", args.user)
        set_user_password(
            token=token,
            upn=args.user,
            new_password=new_password,
            force_change_at_next_signin=args.force_change,
        )
    except RuntimeError as exc:
        logger.error("%s", exc)
        return 1
    except requests.RequestException as exc:
        logger.error("Network error talking to Graph: %s", exc)
        return 1

    # Print result on stdout. Keep this as the LAST stdout write so it's easy
    # to capture the new password with `... | tail -n 2 | head -n 1` in
    # downstream automation, or to redirect into a vault.
    print(f"Password rotated for {args.user}")
    print(f"New password: {new_password}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
