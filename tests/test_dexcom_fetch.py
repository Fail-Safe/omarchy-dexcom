#!/usr/bin/env python3
"""Unit tests for dexcom_fetch.py (no network)."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "dexcom_fetch.py"


def load_module():
    spec = importlib.util.spec_from_file_location("dexcom_fetch", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["dexcom_fetch"] = module
    spec.loader.exec_module(module)
    return module


df = load_module()


class ValidSessionTests(unittest.TestCase):
    def test_accepts_uuid(self):
        sid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        self.assertTrue(df.valid_session(sid))

    def test_rejects_null_and_garbage(self):
        self.assertFalse(df.valid_session(df.NULL_SESSION))
        self.assertFalse(df.valid_session(None))
        self.assertFalse(df.valid_session(123))
        self.assertFalse(df.valid_session("not-a-uuid"))


class ParseStampTests(unittest.TestCase):
    def test_parses_wt_millis(self):
        stamped, age = df.parse_stamp({"WT": "Date(1700000000000)"})
        self.assertEqual(stamped, 1700000000)
        self.assertGreaterEqual(age, 0)

    def test_prefers_wt_over_st(self):
        stamped, _ = df.parse_stamp(
            {
                "WT": "Date(1700000000000)",
                "ST": "Date(1600000000000)",
            }
        )
        self.assertEqual(stamped, 1700000000)

    def test_missing_stamp_returns_negative_age(self):
        stamped, age = df.parse_stamp({})
        self.assertEqual(age, -1)
        self.assertIsInstance(stamped, int)


class NormalizeEntryTests(unittest.TestCase):
    def test_normalizes_value_and_trend(self):
        point = df.normalize_entry(
            {
                "Value": 120,
                "Trend": "Flat",
                "WT": "Date(1700000000000)",
            }
        )
        assert point is not None
        self.assertEqual(point["mgdl"], 120)
        self.assertEqual(point["trend"], "Flat")
        self.assertEqual(point["epochSec"], 1700000000)

    def test_falls_back_to_trend_arrow(self):
        point = df.normalize_entry({"Value": "95", "TrendArrow": "SingleUp"})
        assert point is not None
        self.assertEqual(point["mgdl"], 95)
        self.assertEqual(point["trend"], "SingleUp")

    def test_rejects_missing_or_bad_value(self):
        self.assertIsNone(df.normalize_entry({}))
        self.assertIsNone(df.normalize_entry({"Value": "nope"}))
        self.assertIsNone(df.normalize_entry({"Value": None}))


class NormalizeTests(unittest.TestCase):
    def test_sorts_and_picks_latest(self):
        payload = df.normalize(
            [
                {"Value": 100, "Trend": "Flat", "WT": "Date(1700000000000)"},
                {"Value": 110, "Trend": "SingleUp", "WT": "Date(1700000300000)"},
            ]
        )
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["mgdl"], 110)
        self.assertEqual(payload["trend"], "SingleUp")
        self.assertEqual(len(payload["history"]), 2)
        self.assertEqual(payload["history"][0]["mgdl"], 100)

    def test_missing_points_exits(self):
        with unittest.mock.patch.object(df.sys.stdout, "write"):
            with self.assertRaises(SystemExit) as raised:
                df.normalize([{"Trend": "Flat"}])
        self.assertEqual(raised.exception.code, 1)


class LoadCredentialsTests(unittest.TestCase):
    def test_loads_valid_credentials(self):
        raw = json.dumps(
            {
                "accountName": "caregiver@example.com",
                "password": "secret-password",
                "region": "ous",
            }
        )
        with unittest.mock.patch.object(df, "_read_private_file", return_value=raw):
            creds = df.load_credentials(Path("/tmp/fake-creds.json"))
        self.assertEqual(creds["accountName"], "caregiver@example.com")
        self.assertEqual(creds["region"], "ous")
        self.assertEqual(creds["base"], df.HOSTS["ous"])

    def test_rejects_placeholder_credentials(self):
        raw = json.dumps(
            {
                "accountName": "your-dexcom-share-username",
                "password": "your-dexcom-share-password",
                "region": "us",
            }
        )
        with unittest.mock.patch.object(df, "_read_private_file", return_value=raw):
            with unittest.mock.patch.object(df.sys.stdout, "write"):
                with self.assertRaises(SystemExit) as raised:
                    df.load_credentials(Path("/tmp/fake-creds.json"))
        self.assertEqual(raised.exception.code, 2)

    def test_rejects_invalid_region(self):
        raw = json.dumps(
            {
                "accountName": "caregiver@example.com",
                "password": "secret-password",
                "region": "eu",
            }
        )
        with unittest.mock.patch.object(df, "_read_private_file", return_value=raw):
            with unittest.mock.patch.object(df.sys.stdout, "write"):
                with self.assertRaises(SystemExit) as raised:
                    df.load_credentials(Path("/tmp/fake-creds.json"))
        self.assertEqual(raised.exception.code, 2)


class SessionCacheTests(unittest.TestCase):
    def test_round_trip_private_session_cache(self):
        creds = {
            "accountName": "caregiver@example.com",
            "region": "us",
            "password": "x",
            "applicationId": df.APP_ID,
            "base": df.HOSTS["us"],
        }
        sid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        with tempfile.TemporaryDirectory() as tmp:
            cache_path = Path(tmp) / "session.json"
            df.save_cached_session(cache_path, creds, sid)
            self.assertEqual(cache_path.stat().st_mode & 0o777, 0o600)
            loaded = df.load_cached_session(cache_path, creds)
            self.assertEqual(loaded, sid)

    def test_rejects_mismatched_account(self):
        creds = {
            "accountName": "caregiver@example.com",
            "region": "us",
            "password": "x",
            "applicationId": df.APP_ID,
            "base": df.HOSTS["us"],
        }
        other = dict(creds)
        other["accountName"] = "someone-else@example.com"
        sid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        with tempfile.TemporaryDirectory() as tmp:
            cache_path = Path(tmp) / "session.json"
            df.save_cached_session(cache_path, creds, sid)
            self.assertIsNone(df.load_cached_session(cache_path, other))


class ReadGlucoseTests(unittest.TestCase):
    def test_uses_publisher_list(self):
        entries = [{"Value": 100, "Trend": "Flat", "WT": "Date(1700000000000)"}]

        def fake_http(url, body, timeout=12.0, deadline_sec=20.0):
            if "Publisher" in url:
                return entries, None
            return None, "HTTP 404"

        with unittest.mock.patch.object(df, "http_json", side_effect=fake_http):
            data, error = df.read_glucose(
                {"base": df.HOSTS["us"]},
                "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            )
        self.assertIsNone(error)
        self.assertEqual(data, entries)

    def test_session_invalid_propagates(self):
        with unittest.mock.patch.object(df, "http_json", return_value=(None, "session_invalid")):
            data, error = df.read_glucose(
                {"base": df.HOSTS["us"]},
                "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            )
        self.assertIsNone(data)
        self.assertEqual(error, "session_invalid")


class LoginTests(unittest.TestCase):
    def test_login_by_name_when_account_id_auth_fails(self):
        sid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        creds = {
            "accountName": "caregiver@example.com",
            "password": "secret-password",
            "applicationId": df.APP_ID,
            "base": df.HOSTS["us"],
            "region": "us",
        }

        def fake_http(url, body, timeout=12.0, deadline_sec=20.0):
            if "AuthenticatePublisherAccount" in url:
                return None, "nope"
            if "LoginPublisherAccountByName" in url:
                return sid, None
            return None, "unexpected"

        with unittest.mock.patch.object(df, "http_json", side_effect=fake_http):
            self.assertEqual(df.login(creds), sid)


if __name__ == "__main__":
    unittest.main()
