#!/usr/bin/env python3
"""Generate release-manifest.json describing downloadable assets.

The manifest is attached to every GitHub release, so a website can always
fetch the latest one from a stable URL:

    https://github.com/<owner>/<repo>/releases/latest/download/release-manifest.json

Environment variables:
    ASSET_DIR      Directory with release assets (default: release-assets)
    RELEASE_TAG    Tag name, e.g. v0.1.0 (default: $GITHUB_REF_NAME)
    PUBLISHED_AT   ISO timestamp (default: now UTC)
    GITHUB_REPO    owner/repo (default: xinggue/PeiPal_App)
    GITEE_REPO     owner/repo (default: xinggue/peipal_app)
"""

import glob
import json
import os
from datetime import datetime, timezone

PLATFORM_RULES = (
    (".apk", "android"),
    (".dmg", "macos"),
    ("Setup.exe", "windows_installer"),
    ("Portable.zip", "windows_portable"),
)


def classify(name):
    lower = name.lower()
    for suffix, key in PLATFORM_RULES:
        if lower.endswith(suffix.lower()):
            return key
    return None


def main():
    asset_dir = os.environ.get("ASSET_DIR", "release-assets").strip()
    tag = os.environ.get("RELEASE_TAG", "").strip() or os.environ.get(
        "GITHUB_REF_NAME", ""
    ).strip()
    published_at = os.environ.get("PUBLISHED_AT", "").strip() or datetime.now(
        timezone.utc
    ).strftime("%Y-%m-%dT%H:%M:%SZ")
    gh_repo = os.environ.get("GITHUB_REPO", "xinggue/PeiPal_App").strip()
    gitee_repo = os.environ.get("GITEE_REPO", "xinggue/peipal_app").strip()

    platforms = {}
    for path in sorted(glob.glob(os.path.join(asset_dir, "*"))):
        if not os.path.isfile(path):
            continue
        name = os.path.basename(path)
        if name == "release-manifest.json":
            continue
        key = classify(name)
        if not key:
            continue
        platforms[key] = {
            "name": name,
            "size": os.path.getsize(path),
            "github": f"https://github.com/{gh_repo}/releases/download/{tag}/{name}",
            "gitee": f"https://gitee.com/{gitee_repo}/releases/download/{tag}/{name}",
        }

    manifest = {
        "version": tag,
        "published_at": published_at,
        "source": {"github": gh_repo, "gitee": gitee_repo},
        "links": {
            "github_release": f"https://github.com/{gh_repo}/releases/tag/{tag}",
            "gitee_release": f"https://gitee.com/{gitee_repo}/releases/tag/{tag}",
        },
        "platforms": platforms,
    }

    out = os.path.join(asset_dir, "release-manifest.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"Wrote {out}")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
