"""Check core release files and report the uncompressed Windows bundle size."""

import os
from pathlib import Path
import sys


REQUIRED_FILES = (
    "peipal.exe",
    "flutter_windows.dll",
    "data/app.so",
    "data/icudtl.dat",
    "data/flutter_assets/AssetManifest.bin",
    "data/flutter_assets/assets/data/icd_knowledge.db",
)


def verify_bundle(root: Path) -> str:
    missing = [
        name
        for name in REQUIRED_FILES
        if not (root / name).is_file() or (root / name).stat().st_size == 0
    ]
    if missing:
        raise ValueError("Missing or empty release files: " + ", ".join(missing))
    if (root / "data/flutter_assets/kernel_blob.bin").exists():
        raise ValueError("Debug kernel found in the release bundle")

    files = sorted(
        ((file.stat().st_size, file.relative_to(root).as_posix())
         for file in root.rglob("*") if file.is_file()),
        reverse=True,
    )
    total = sum(size for size, _ in files)
    lines = [
        "## Windows release bundle",
        "",
        f"{len(files)} files, {total / 1024 / 1024:.1f} MiB before compression.",
        "",
        "| File | MiB |",
        "| --- | ---: |",
    ]
    lines.extend(f"| {name} | {size / 1024 / 1024:.2f} |"
                 for size, name in files[:15])
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    try:
        report = verify_bundle(Path(sys.argv[1]))
    except (IndexError, ValueError) as error:
        sys.exit(str(error))
    print(report)
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a", encoding="utf-8") as output:
            output.write(report)
