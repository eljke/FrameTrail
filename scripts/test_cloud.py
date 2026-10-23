#!/usr/bin/env python3
"""Exercise a deployed backend with two disposable, confirmed test accounts."""

import argparse
import copy
import json
from pathlib import Path
import plistlib
import urllib.error
import urllib.request
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--accounts", type=Path, required=True,
                        help="Private JSON file containing two disposable email/password accounts")
    args = parser.parse_args()
    config = plistlib.loads((Path(__file__).resolve().parents[1] / "FrameTrail/Supabase.plist").read_bytes())
    accounts = json.loads(args.accounts.read_text())
    assert len(accounts) == 2, "Two disposable accounts are required"

    def call(path, token=None, body=None, method="GET"):
        headers = {"apikey": config["publishableKey"], "Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        request = urllib.request.Request(config["projectURL"] + path,
                                         data=json.dumps(body).encode() if body is not None else None,
                                         headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read(2 * 1024 * 1024)
                return response.status, json.loads(data) if data else None
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def login(account):
        status, session = call("/auth/v1/token?grant_type=password", body={"email": account["email"], "password": account["password"]}, method="POST")
        assert status == 200, f"Test account login failed: HTTP {status}"
        return session

    sessions = []
    try:
        first = login(accounts[0])
        sessions.append(first)
        second_device = login(accounts[0])
        other = login(accounts[1])
        sessions.append(other)
        status, refreshed = call("/auth/v1/token?grant_type=refresh_token", body={"refresh_token": first["refresh_token"]}, method="POST")
        assert status == 200 and refreshed["user"]["id"] == first["user"]["id"], "Session refresh failed"
        first = refreshed
        sessions[0] = first
        media_id = "local:integration-" + uuid.uuid4().hex
        review = {"id": str(uuid.uuid4()), "titleID": media_id, "summary": "A saved personal impression. " * 80,
                  "liked": ["Acting"], "disliked": ["Pacing"], "questions": [], "rating": 9, "createdAt": 0,
                  "episodeID": "e1", "episodeSeason": 1, "episodeNumber": 1,
                  "likedChoices": [{"id": "plot#0:characters", "aspect": "characters", "text": "A decision to return home",
                                    "sourceQuote": "A character decides to return home.", "sourceID": "plot", "episodeID": "e1",
                                    "sourceURL": "https://en.wikipedia.org/w/index.php?oldid=123"}], "dislikedChoices": []}
        reviews = [dict(copy.deepcopy(review), id=str(uuid.uuid4())) for _ in range(80)]
        item = {"title": {"id": media_id, "title": "Integration series", "kind": "series", "overview": "", "provider": "local", "providerID": media_id},
                "progress": {"finished": False, "watchedEpisodeIDs": ["e1"]}, "reflections": reviews}
        assert 128 * 1024 < len(json.dumps(item).encode()) < 512 * 1024, "Capacity regression fixture must exercise the expanded record limit"

        def put(session, payload, revision):
            return call("/rest/v1/rpc/put_library_item", session["access_token"],
                        {"p_media_id": media_id, "p_payload": payload, "p_expected_revision": revision, "p_deleted": payload is None}, "POST")

        def read(session):
            status, rows = call("/rest/v1/library_items?select=media_id,payload,revision,deleted", session["access_token"])
            assert status == 200, f"Library read failed: HTTP {status}"
            return rows

        status, rows = put(first, item, 0)
        assert status == 200 and len(rows) == 1 and rows[0]["revision"] == 1, f"Initial write failed: HTTP {status}"
        assert read(second_device)[0]["payload"] == item, "Second device did not receive the library"
        assert read(other) == [], "An account read another owner's records"
        changed = copy.deepcopy(item)
        changed["progress"]["finished"] = True
        status, rows = put(second_device, changed, 1)
        assert status == 200 and rows[0]["revision"] == 2
        status, rows = put(first, item, 1)
        assert status == 200 and rows == [], "A stale write overwrote a newer version"
        assert read(first)[0]["payload"]["progress"]["finished"] is True
        status, rows = put(other, item, 2)
        assert status == 200 and rows == [], "Another account changed the owner's record"
        status, rows = put(other, item, 0)
        assert status == 200 and rows[0]["revision"] == 1, "Independent account namespace failed"
        assert read(first)[0]["revision"] == 2
        status, _ = call("/rest/v1/library_items?media_id=eq." + media_id, first["access_token"], {"deleted": True}, "PATCH")
        assert status in (401, 403), "Direct writes bypassed revision checks"
        status, _ = call("/rest/v1/library_items?select=media_id")
        assert status in (401, 403), "Anonymous read was permitted"
        status, rows = put(first, None, 2)
        assert status == 200 and rows[0]["deleted"] and rows[0]["revision"] == 3
        assert read(second_device)[0]["deleted"], "Deletion did not propagate"
        status, _ = call("/functions/v1/delete-account", "invalid-token", method="DELETE")
        assert status == 401, "Unauthenticated account deletion was permitted"
        print("Passed: password login, refresh, second-device review/choice round-trip above 128 KiB, owner isolation, CAS conflict, direct-write denial, anonymous denial, deletion tombstone, invalid-token denial.")
    finally:
        for session in sessions:
            status, _ = call("/functions/v1/delete-account", session["access_token"], method="DELETE")
            assert status == 204, f"Disposable account cleanup failed: HTTP {status}"
        if sessions:
            print("Passed: authenticated account deletion and disposable-account cleanup.")


if __name__ == "__main__":
    main()
