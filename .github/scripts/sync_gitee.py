#!/usr/bin/env python3
"""Sync release assets to a Gitee release.

Usage:
    GITEE_TOKEN=xxx RELEASE_TAG=v0.1.0 ASSET_DIR=release-assets \
        python3 sync_gitee.py

Environment variables:
    GITEE_TOKEN   Gitee personal access token (scope: projects)
    RELEASE_TAG   Release tag name, e.g. v0.1.0
    ASSET_DIR     Directory containing the files to upload (default: release-assets)
    GITEE_OWNER   Gitee user or org (default: xinggue)
    GITEE_REPO    Gitee repo name (default: peipal_app)
    GITEE_TARGET  target_commitish for release creation (default: main)
"""

import glob
import json
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request

API = "https://gitee.com/api/v5"
UA = {"User-Agent": "Mozilla/5.0"}


def request(method, url, data=None, headers=None):
    h = dict(UA)
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        return -1, str(e)


def main():
    token = os.environ.get("GITEE_TOKEN", "").strip()
    tag = os.environ.get("RELEASE_TAG", "").strip()
    asset_dir = os.environ.get("ASSET_DIR", "release-assets").strip()
    owner = os.environ.get("GITEE_OWNER", "xinggue").strip()
    repo = os.environ.get("GITEE_REPO", "peipal_app").strip()
    target = os.environ.get("GITEE_TARGET", "main").strip()

    if not token:
        print("No GITEE_TOKEN provided, skipping Gitee release sync.")
        return
    if not tag:
        print("No RELEASE_TAG provided, skipping Gitee release sync.")
        return

    print(f"Syncing release {tag} to Gitee ({owner}/{repo}) from '{asset_dir}'...")

    release_id = None
    status, body = request(
        "GET",
        f"{API}/repos/{owner}/{repo}/releases/tags/{tag}"
        f"?access_token={urllib.parse.quote(token)}",
    )
    print(f"GET release by tag -> HTTP {status}")
    if status == 200:
        try:
            data = json.loads(body)
        except Exception:  # noqa: BLE001
            data = None
        if isinstance(data, dict):
            release_id = data.get("id")
    if release_id:
        print(f"Found existing Gitee release ID: {release_id}")

    if not release_id:
        payload = urllib.parse.urlencode(
            {
                "access_token": token,
                "tag_name": tag,
                "name": f"Release {tag}",
                "target_commitish": target,
                "prerelease": "false",
                "body": (
                    f"PeiPal (小培同学) {tag} 多平台发布版本。\n\n"
                    "包含 Android 安装包、macOS 镜像、Windows 安装程序及便携版。\n"
                    "国内镜像高速下载。"
                ),
            }
        ).encode("utf-8")
        status, body = request(
            "POST",
            f"{API}/repos/{owner}/{repo}/releases",
            data=payload,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        print(f"POST create release -> HTTP {status}")
        print(f"Response: {body[:800]}")
        if status in (200, 201):
            try:
                data = json.loads(body)
            except Exception:  # noqa: BLE001
                data = None
            if isinstance(data, dict):
                release_id = data.get("id")

    if not release_id:
        print("ERROR: Unable to obtain a Gitee release ID, aborting asset upload.")
        return

    print(f"Using Gitee release ID: {release_id}")

    files = sorted(glob.glob(os.path.join(asset_dir, "*")))
    print(f"Uploading {len(files)} files to Gitee release {release_id}...")
    for f in files:
        if not os.path.isfile(f):
            continue
        fname = os.path.basename(f)
        print(f"--> Uploading {fname} ...")
        cmd = [
            "curl", "-sS", "--retry", "3", "--max-time", "600",
            "-X", "POST",
            "-F", f"access_token={token}",
            "-F", f"file=@{f}",
            f"{API}/repos/{owner}/{repo}/releases/{release_id}/attach_files",
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        out = (res.stdout or "").strip()
        print(f"    HTTP result (exit {res.returncode}): {out[:400]}")
        if res.returncode != 0:
            print(f"    Warning: curl error: {res.stderr.strip()[:400]}")

    print("Gitee release synchronization completed!")


if __name__ == "__main__":
    main()
