#!/usr/bin/env python3
"""Edit a clip with the Aisma REST API: upload, price, confirm, start, wait, download.

Usage:
    pip install requests
    export AISMA_API_KEY=aisma_live_...
    python3 edit.py clip.mp4 "change the background to a snowy forest" [720p|1080p]

Nothing is charged until you answer "y" to the price question.
"""
import os
import sys
import time

import requests

API = "https://api.aisma.ai/v1"
USER_AGENT = "aisma-example-python/1.0"  # use your own app name

session = requests.Session()
session.headers.update({
    "Authorization": f"Bearer {os.environ['AISMA_API_KEY']}",
    "User-Agent": USER_AGENT,
})


def call(method, path, **kwargs):
    response = session.request(method, API + path, timeout=60, **kwargs)
    if response.status_code >= 400:
        try:
            error = response.json()["error"]
            detail = f"{error['code']}: {error['message']}"
        except (ValueError, KeyError):
            detail = response.text[:200]
        request_id = response.headers.get("X-Request-Id", "-")
        sys.exit(f"{method} {path} failed ({response.status_code}) {detail} [request {request_id}]")
    return response


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path, brief = sys.argv[1], sys.argv[2]
    quality = sys.argv[3] if len(sys.argv) > 3 else "720p"
    content_type = "video/quicktime" if path.lower().endswith(".mov") else "video/mp4"

    # 1. Ask for a one-time upload link, then PUT the file there with the headers it names.
    upload = call("POST", "/uploads", json={
        "kind": "video", "contentType": content_type, "bytes": os.path.getsize(path),
    }).json()
    with open(path, "rb") as file:
        put = requests.put(
            upload["uploadUrl"], data=file, timeout=900,
            headers={"Content-Type": content_type, "User-Agent": USER_AGENT, **upload["headers"]},
        )
    put.raise_for_status()

    # 2. Wait until Aisma has checked the clip.
    asset_id = upload["assetId"]
    while True:
        asset = call("GET", f"/assets/{asset_id}").json()
        if asset["status"] == "ready":
            break
        if asset["status"] in ("failed", "expired"):
            sys.exit(f"Upload {asset['status']}: {asset.get('error')}")
        time.sleep(3)

    # 3. Price the edit. Nothing is charged; a 202 means "ask again after retryAfterMs".
    while True:
        response = call("POST", "/quotes", json={"sourceId": asset_id, "brief": brief, "quality": quality})
        quote = response.json()
        if response.status_code != 202:
            break
        time.sleep(quote["retryAfterMs"] / 1000)

    answer = input(f"Start this edit for {quote['credits']} credits? [y/N] ")
    if answer.strip().lower() != "y":
        print("Not started. Nothing was charged.")
        return

    # 4. Start it. The Idempotency-Key makes a retry return the same edit.
    job = call("POST", "/jobs", json={"quoteId": quote["id"]},
               headers={"Idempotency-Key": f"edit-{quote['id']}"}).json()
    job_id = job["jobId"]
    print(f"Started edit {job_id}")

    # 5. Follow it (no more often than every 10 seconds), then fetch the one-hour link.
    while True:
        status = call("GET", f"/jobs/{job_id}").json()
        print(f"  {status['stage']} {status['progress']}%")
        if status["resultReady"]:
            break
        if status["status"] == "failed":
            sys.exit(f"The edit failed: {status.get('issues')}")
        time.sleep(10)

    link = call("POST", f"/jobs/{job_id}/result").json()
    out = os.path.splitext(path)[0] + "-edited.mp4"
    with requests.get(link["url"], stream=True, timeout=900, headers={"User-Agent": USER_AGENT}) as download:
        download.raise_for_status()
        with open(out, "wb") as file:
            for chunk in download.iter_content(chunk_size=1 << 20):
                file.write(chunk)
    print(f"Saved {out}. The edit is also in your Aisma Library.")


if __name__ == "__main__":
    main()
