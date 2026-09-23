#!/usr/bin/env python3
"""Find or create the editable Next Cue App Store version."""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE_ID = "com.jackwallner.adhd"
APP_STORE_CONNECT_APP_ID = "6815023447"


def main() -> None:
    client = asc_lib.ASCClient.from_credentials()
    app = asc_lib.find_app(client, BUNDLE_ID)
    if app["id"] != APP_STORE_CONNECT_APP_ID:
        raise SystemExit(
            f"error: {BUNDLE_ID} resolved to ASC app {app['id']}, "
            f"expected {APP_STORE_CONNECT_APP_ID}"
        )

    state = asc_lib.load_state()
    preferred = os.environ.get("ASC_DRAFT_VERSION") or os.environ.get("ASC_APP_VERSION")
    if preferred is None and state.get("draftVersion"):
        preferred = state["draftVersion"]
    live = asc_lib.find_live_version(client, app["id"])
    draft = asc_lib.ensure_draft_version(client, app["id"], preferred)
    version = draft["attributes"]["versionString"]
    live_version = live["attributes"]["versionString"] if live else None
    asc_lib.save_state(version, live_version, app["id"])

    print(f"draftVersion={version} ({draft['attributes'].get('appStoreState')})")
    if live_version:
        print(f"liveVersion={live_version}")
    print(f"export ASC_APP_VERSION='{version}'")


if __name__ == "__main__":
    main()
