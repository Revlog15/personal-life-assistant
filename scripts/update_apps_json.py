#!/usr/bin/env python3
"""Update SideStore/AltStore apps.json with a new GitHub Release entry."""
import argparse
import datetime
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Update apps.json for SideStore source")
    parser.add_argument("--apps-json", required=True, type=Path)
    parser.add_argument("--version", required=True, help="Marketing version, e.g. 1.0.0")
    parser.add_argument("--build", required=True, help="Build number, e.g. 42")
    parser.add_argument("--download-url", required=True, help="Direct HTTPS URL to .ipa")
    parser.add_argument("--size", required=True, type=int, help="IPA size in bytes")
    parser.add_argument("--min-os", default="17.0")
    parser.add_argument(
        "--notes",
        default="Rilis Personal Life Assistant v2.1.0 (Full PRD v0.2: MVP + Pasca-MVP lengkap termasuk Share Extension OCR native P-06, WidgetKit Home 2x2/4x2 & Lock Screen P-07, Diagnostik App Group V-07).",
    )
    args = parser.parse_args()

    data = json.loads(args.apps_json.read_text(encoding="utf-8"))
    today = datetime.date.today().isoformat()

    entry = {
        "version": args.version,
        "buildVersion": str(args.build),
        "date": today,
        "localizedDescription": args.notes,
        "downloadURL": args.download_url,
        "size": args.size,
        "minOSVersion": args.min_os,
    }

    app = data["apps"][0]
    app["downloadURL"] = args.download_url
    versions = [v for v in app.get("versions", []) if v.get("version") != args.version]
    versions.insert(0, entry)
    app["versions"] = versions

    args.apps_json.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"Updated {args.apps_json} with version {args.version} (build {args.build}, {args.size} bytes)")


if __name__ == "__main__":
    main()
