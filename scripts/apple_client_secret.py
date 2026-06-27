#!/usr/bin/env python3
"""
Generates the "Secret Key (for OAuth)" JWT that Supabase's Apple provider needs.

Dependencies are already installed in scripts/.venv.

All inputs come from environment variables so no personal identifiers or key
paths live in this (public) repo. Set them, then run from the scripts/ folder:

    export APPLE_TEAM_ID="XXXXXXXXXX"
    export APPLE_SERVICES_ID="com.yourcompany.app.signin"
    export APPLE_KEY_ID="XXXXXXXXXX"
    export APPLE_P8_PATH="/absolute/path/to/AuthKey_XXXXXXXXXX.p8"
    .venv/bin/python apple_client_secret.py

(Tip: keep these in an untracked scripts/.env and `source` it before running.)

Paste the printed token into Supabase -> Authentication -> Providers -> Apple ->
"Secret Key (for OAuth)". Apple lets this JWT live up to 6 months -- re-run this
script and update Supabase before it expires.
"""
import os
import sys
import time
import jwt  # PyJWT

# ---- All inputs from the environment (nothing sensitive hardcoded) ----------
TEAM_ID     = os.environ.get("APPLE_TEAM_ID")       # your Apple Team ID
SERVICES_ID = os.environ.get("APPLE_SERVICES_ID")   # the Services ID (OAuth client_id)
KEY_ID      = os.environ.get("APPLE_KEY_ID")        # 10-char Key ID of the Sign in with Apple key
P8_PATH     = os.environ.get("APPLE_P8_PATH")       # absolute path to the downloaded .p8
# -----------------------------------------------------------------------------

missing = [name for name, val in [
    ("APPLE_TEAM_ID", TEAM_ID),
    ("APPLE_SERVICES_ID", SERVICES_ID),
    ("APPLE_KEY_ID", KEY_ID),
    ("APPLE_P8_PATH", P8_PATH),
] if not val]
if missing:
    sys.exit("Missing required environment variable(s): " + ", ".join(missing) +
             "\nSee the instructions at the top of this file.")

try:
    with open(P8_PATH, "r") as f:
        private_key = f.read()
except OSError as e:
    sys.exit(f"Could not read APPLE_P8_PATH ({P8_PATH}): {e}")

now = int(time.time())
token = jwt.encode(
    {
        "iss": TEAM_ID,
        "iat": now,
        "exp": now + 86400 * 180,          # 180 days (Apple max is 6 months)
        "aud": "https://appleid.apple.com",
        "sub": SERVICES_ID,
    },
    private_key,
    algorithm="ES256",
    headers={"kid": KEY_ID},
)

print("\nApple client secret (paste into Supabase 'Secret Key for OAuth'):\n")
print(token)
print()
