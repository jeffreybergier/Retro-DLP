#!/usr/bin/env python3

"""Compare Retro-DLP's live result with the pinned yt-dlp extractor."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


VIDEO_ID = "YE7VzlLtp-4"
IMPORTANT_QUERY_FIELDS = (
    "itag",
    "source",
    "requiressl",
    "mime",
    "ratebypass",
    "dur",
    "lmt",
    "c",
    "txp",
)


def fail(message):
    raise RuntimeError(message)


def run_json(command):
    process = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if process.returncode != 0:
        fail(
            f"command failed ({process.returncode}): {' '.join(command)}\n"
            f"{process.stderr.strip()}"
        )
    try:
        return json.loads(process.stdout)
    except json.JSONDecodeError as error:
        fail(f"command returned invalid JSON: {error}")


def split_media_url(value):
    parsed = urllib.parse.urlsplit(value)
    if not parsed.hostname or not parsed.hostname.endswith(".googlevideo.com"):
        fail(f"unexpected media host: {parsed.hostname!r}")
    return parsed, urllib.parse.parse_qs(parsed.query)


def head_status(url, headers):
    request = urllib.request.Request(url, headers=headers, method="HEAD")
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except urllib.error.URLError as error:
        fail(f"yt-dlp media HEAD failed: {error}")


def classification(status):
    if status == 403:
        return "po_token_required"
    if 200 <= status < 400:
        return "ok"
    return "http_error"


def main():
    if len(sys.argv) not in (3, 4):
        fail("usage: yt_dlp_oracle.py RETRO_DLP YT_DLP_MAIN [COOKIES]")
    binary, yt_dlp_main = sys.argv[1:3]
    cookie_file = sys.argv[3] if len(sys.argv) == 4 else None
    video_url = f"https://www.youtube.com/watch?v={VIDEO_ID}"

    retro_command = [binary]
    if cookie_file:
        retro_command.extend(["--cookies", cookie_file])
    retro_command.extend(["--no-download", VIDEO_ID])
    retro = run_json(retro_command)
    oracle_command = [
            sys.executable,
            yt_dlp_main,
            "--ignore-config",
            "--no-warnings",
            "--no-playlist",
            "--skip-download",
            "--js-runtimes",
            "node",
            "--remote-components",
            "ejs:github",
            "--extractor-args",
            "youtube:player_client=mweb",
            "-f",
            "best[height<=720][ext=mp4]",
            "--dump-single-json",
            video_url,
        ]
    oracle_cookie_file = None
    try:
        if cookie_file:
            descriptor, oracle_cookie_file = tempfile.mkstemp(
                prefix="retro-dlp-yt-dlp-cookies."
            )
            os.close(descriptor)
            shutil.copyfile(cookie_file, oracle_cookie_file)
            os.chmod(oracle_cookie_file, 0o600)
            oracle_command[2:2] = ["--cookies", oracle_cookie_file]
        oracle = run_json(oracle_command)
    finally:
        if oracle_cookie_file:
            os.unlink(oracle_cookie_file)

    expected_metadata = {
        "itag": int(oracle["format_id"]),
        "width": oracle["width"],
        "height": oracle["height"],
    }
    actual_metadata = {name: retro[name] for name in expected_metadata}
    if actual_metadata != expected_metadata:
        fail(
            f"format metadata differs: Retro-DLP={actual_metadata}, "
            f"yt-dlp={expected_metadata}"
        )
    if not retro["mimeType"].startswith("video/mp4") or oracle["ext"] != "mp4":
        fail("Retro-DLP and yt-dlp did not both select MP4")

    retro_url, retro_query = split_media_url(retro["url"])
    oracle_url, oracle_query = split_media_url(oracle["url"])
    for field in IMPORTANT_QUERY_FIELDS:
        if retro_query.get(field) != oracle_query.get(field):
            fail(
                f"media query field {field!r} differs: "
                f"Retro-DLP={retro_query.get(field)}, "
                f"yt-dlp={oracle_query.get(field)}"
            )

    # Signature and transformed n bytes vary per player request, so compare the
    # signature parameter choice and the presence of an n query parameter.
    retro_signature_names = {
        name for name in ("sig", "signature") if name in retro_query
    }
    oracle_signature_names = {
        name for name in ("sig", "signature") if name in oracle_query
    }
    if retro_signature_names != oracle_signature_names or not retro_signature_names:
        fail(
            "direct signature parameters differ: "
            f"Retro-DLP={retro_signature_names}, yt-dlp={oracle_signature_names}"
        )
    if ("n" in retro_query) != ("n" in oracle_query):
        fail(
            "n parameter presence differs: "
            f"Retro-DLP={'n' in retro_query}, yt-dlp={'n' in oracle_query}"
        )

    retro_status = head_status(retro["url"], retro.get("headers", {}))
    oracle_status = head_status(oracle["url"], oracle.get("http_headers", {}))
    oracle_classification = classification(oracle_status)
    if retro_status != oracle_status:
        fail(
            f"HEAD status differs: Retro-DLP={retro_status}, "
            f"yt-dlp={oracle_status}"
        )

    print(
        "PASS: live yt-dlp oracle "
        f"(itag {retro['itag']}, Google Video media service, HTTP {oracle_status} "
        f"{oracle_classification})"
    )


if __name__ == "__main__":
    try:
        main()
    except (KeyError, TypeError, ValueError, RuntimeError) as error:
        print(f"FAIL: yt-dlp oracle comparison: {error}", file=sys.stderr)
        sys.exit(1)
