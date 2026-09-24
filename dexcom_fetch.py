#!/usr/bin/env python3
"""Fetch latest Dexcom Share glucose. Credentials loaded from a JSON file only."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

APP_ID = "d89443d2-327c-4a6f-89e5-496bbb0317db"
HOSTS = {
    "us": "https://share2.dexcom.com",
    "ous": "https://shareous1.dexcom.com",
}
USER_AGENT = "Dexcom Share/3.0.2.11"
NULL_SESSION = "00000000-0000-0000-0000-000000000000"
SESSION_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
PLACEHOLDER_ACCOUNTS = {
    "your-dexcom-share-username",
    "your-username",
    "username",
    "account",
}
PLACEHOLDER_PASSWORDS = {
    "your-dexcom-share-password",
    "your-password",
    "password",
    "changeme",
}


def emit(payload: dict, code: int = 0) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")))
    sys.stdout.write("\n")
    raise SystemExit(code)


def valid_session(session_id: object) -> bool:
    if not isinstance(session_id, str):
        return False
    if session_id == NULL_SESSION:
        return False
    return bool(SESSION_RE.match(session_id))


def load_credentials(path: Path) -> dict:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        emit({"ok": False, "error": f"Credentials file missing: {path}"}, 2)
    except OSError as exc:
        emit({"ok": False, "error": f"Cannot read credentials: {exc}"}, 2)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        emit({"ok": False, "error": "Credentials file is not valid JSON"}, 2)
    if not isinstance(data, dict):
        emit({"ok": False, "error": "Credentials file must be a JSON object"}, 2)
    account = str(data.get("accountName") or data.get("username") or "").strip()
    password = str(data.get("password") or "")
    region = str(data.get("region") or "us").strip().lower()
    application_id = str(data.get("applicationId") or APP_ID).strip() or APP_ID
    if not account or not password:
        emit({"ok": False, "error": "Credentials need accountName and password"}, 2)
    if account.lower() in PLACEHOLDER_ACCOUNTS or password.lower() in PLACEHOLDER_PASSWORDS:
        emit(
            {
                "ok": False,
                "error": "Edit ~/.config/omarchy/dexcom-share.json with your Dexcom Share login",
            },
            2,
        )
    if region not in HOSTS:
        emit({"ok": False, "error": "region must be us or ous"}, 2)
    return {
        "accountName": account,
        "password": password,
        "region": region,
        "applicationId": application_id,
        "base": HOSTS[region],
    }


def http_json(url: str, body: dict, timeout: float = 12.0):
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8", errors="replace").strip()
            status = getattr(response, "status", 200)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace").strip()
        message = detail or f"HTTP {exc.code}"
        if exc.code in (401, 500) and "SessionNotValid" in detail:
            return None, "session_invalid"
        return None, message[:240]
    except urllib.error.URLError as exc:
        return None, f"Network error: {exc.reason}"
    except TimeoutError:
        return None, "Request timed out"
    if not raw:
        return None if status >= 400 else "", None
    try:
        return json.loads(raw), None
    except json.JSONDecodeError:
        if raw.startswith('"') and raw.endswith('"'):
            return json.loads(raw), None
        return None, "Unexpected non-JSON response"


def login(creds: dict) -> str:
    # Prefer account-id auth (works for Share follower/publisher), fall back to name login.
    account_id = authenticate_account_id(creds)
    if account_id:
        session_id = login_with_id(creds, account_id)
        if session_id:
            return session_id

    url = f"{creds['base']}/ShareWebServices/Services/General/LoginPublisherAccountByName"
    body = {
        "accountName": creds["accountName"],
        "password": creds["password"],
        "applicationId": creds["applicationId"],
    }
    data, error = http_json(url, body)
    if error:
        emit({"ok": False, "error": f"Login failed: {error}"}, 1)
    session_id = data if isinstance(data, str) else None
    if not valid_session(session_id):
        emit(
            {
                "ok": False,
                "error": "Login failed: check Dexcom Share username/password and region (us|ous)",
            },
            1,
        )
    return session_id


def authenticate_account_id(creds: dict) -> str | None:
    url = f"{creds['base']}/ShareWebServices/Services/General/AuthenticatePublisherAccount"
    body = {
        "accountName": creds["accountName"],
        "password": creds["password"],
        "applicationId": creds["applicationId"],
    }
    data, error = http_json(url, body)
    if error or not isinstance(data, str) or not SESSION_RE.match(data) or data == NULL_SESSION:
        return None
    return data


def login_with_id(creds: dict, account_id: str) -> str | None:
    url = f"{creds['base']}/ShareWebServices/Services/General/LoginPublisherAccountById"
    body = {
        "accountId": account_id,
        "password": creds["password"],
        "applicationId": creds["applicationId"],
    }
    data, error = http_json(url, body)
    if error or not valid_session(data):
        return None
    return data


def read_glucose(creds: dict, session_id: str, minutes: int = 1440, max_count: int = 1):
    paths = [
        "/ShareWebServices/Services/Publisher/ReadPublisherLatestGlucoseValues",
        "/ShareWebServices/Services/Subscriber/ReadSubscriberLatestGlucoseValues",
    ]
    last_error = "No recent glucose values"
    for path in paths:
        url = f"{creds['base']}{path}"
        body = {"sessionId": session_id, "minutes": int(minutes), "maxCount": int(max_count)}
        data, error = http_json(url, body)
        if error == "session_invalid":
            return None, "session_invalid"
        if error:
            # 404 means this account role does not expose that endpoint.
            if "HTTP 404" in error or '"Code":"ResourceNotFound"' in error or "ResourceNotFound" in error:
                last_error = error
                continue
            return None, error
        if data == "" or data is None:
            last_error = "Empty glucose response"
            continue
        if not isinstance(data, list):
            last_error = "Unexpected glucose response"
            continue
        if not data:
            last_error = "No recent glucose values"
            continue
        return data, None
    return None, last_error


def parse_stamp(entry: dict) -> tuple[int, int]:
    now = int(time.time())
    for key in ("WT", "ST", "DT"):
        value = entry.get(key)
        if not isinstance(value, str):
            continue
        match = re.search(r"Date\((\d+)\)", value)
        if not match:
            continue
        millis = int(match.group(1))
        stamped = millis // 1000
        return stamped, max(0, now - stamped)
    return now, -1


def normalize_entry(entry: dict) -> dict | None:
    mgdl = entry.get("Value")
    try:
        mgdl_int = int(mgdl)
    except (TypeError, ValueError):
        return None
    trend = entry.get("Trend")
    if trend is None:
        trend = entry.get("TrendArrow") or "None"
    stamped_at, age_sec = parse_stamp(entry)
    return {
        "mgdl": mgdl_int,
        "trend": trend,
        "stampedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(stamped_at)),
        "ageSec": age_sec,
        "epochSec": stamped_at,
    }


def normalize(entries: list) -> dict:
    points = []
    for entry in entries:
        point = normalize_entry(entry)
        if point is not None:
            points.append(point)
    if not points:
        emit({"ok": False, "error": "Glucose value missing"}, 1)
    # Dexcom usually returns newest-first; sort ascending for charts.
    points.sort(key=lambda item: item["epochSec"])
    latest = points[-1]
    return {
        "ok": True,
        "mgdl": latest["mgdl"],
        "trend": latest["trend"],
        "stampedAt": latest["stampedAt"],
        "ageSec": latest["ageSec"],
        "history": points,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch Dexcom Share glucose")
    parser.add_argument(
        "--credentials",
        default=os.path.expanduser("~/.config/omarchy/dexcom-share.json"),
        help="Path to credentials JSON (never pass password on argv)",
    )
    parser.add_argument(
        "--session-cache",
        default=os.path.expanduser("~/.cache/omarchy-dexcom/session.json"),
        help="Optional session cache path",
    )
    parser.add_argument(
        "--minutes",
        type=int,
        default=1440,
        help="History window in minutes (default 1440 = 24h)",
    )
    parser.add_argument(
        "--max-count",
        type=int,
        default=288,
        help="Max readings to fetch (default 288 ~= 24h at 5 min)",
    )
    args = parser.parse_args()
    minutes = max(5, min(1440, int(args.minutes)))
    max_count = max(1, min(288, int(args.max_count)))
    creds = load_credentials(Path(args.credentials).expanduser())
    cache_path = Path(args.session_cache).expanduser()

    session_id = None
    if cache_path.is_file():
        try:
            cached = json.loads(cache_path.read_text(encoding="utf-8"))
            if (
                isinstance(cached, dict)
                and cached.get("accountName") == creds["accountName"]
                and cached.get("region") == creds["region"]
                and valid_session(str(cached.get("sessionId") or ""))
            ):
                session_id = str(cached["sessionId"])
        except (OSError, json.JSONDecodeError, TypeError):
            session_id = None

    if not session_id:
        session_id = login(creds)

    entries, error = read_glucose(creds, session_id, minutes=minutes, max_count=max_count)
    if error == "session_invalid":
        session_id = login(creds)
        entries, error = read_glucose(creds, session_id, minutes=minutes, max_count=max_count)
    if error:
        emit({"ok": False, "error": f"Glucose fetch failed: {error}"}, 1)

    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(
            json.dumps(
                {
                    "accountName": creds["accountName"],
                    "region": creds["region"],
                    "sessionId": session_id,
                }
            ),
            encoding="utf-8",
        )
        os.chmod(cache_path, 0o600)
    except OSError:
        pass

    emit(normalize(entries), 0)


if __name__ == "__main__":
    main()
