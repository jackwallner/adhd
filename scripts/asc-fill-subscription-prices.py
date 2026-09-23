#!/usr/bin/env python3
"""Give every available territory a subscription price.

The API does not equalize subscription prices on its own, so a subscription
with only USA and PPP prices stays MISSING_METADATA. This adds Apple's
equalized price for each territory that has no price yet and leaves existing
prices (USA base and PPP overrides) untouched. Prelaunch only.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A

BUNDLE_ID = "com.jackwallner.adhd"


def price_territories(c: A.ASCClient, sub_id: str) -> tuple[set[str], str]:
    """Territories that already have a price, and the USA price point id."""
    rows = c.get(f"/subscriptions/{sub_id}/prices?include=territory,subscriptionPricePoint&limit=200")
    have, usa_point = set(), None
    for row in rows["data"]:
        territory = row["relationships"]["territory"]["data"]["id"]
        have.add(territory)
        if territory == "USA":
            usa_point = row["relationships"]["subscriptionPricePoint"]["data"]["id"]
    if usa_point is None:
        raise SystemExit(f"{sub_id}: no USA base price")
    return have, usa_point


def main() -> None:
    c = A.ASCClient.from_credentials()
    app = A.find_app(c, BUNDLE_ID)
    for group in A.list_all(c, f"/apps/{app['id']}/subscriptionGroups"):
        for sub in A.list_all(c, f"/subscriptionGroups/{group['id']}/subscriptions"):
            sid, pid = sub["id"], sub["attributes"]["productId"]
            have, usa_point = price_territories(c, sid)
            equalized = A.list_all(c, f"/subscriptionPricePoints/{usa_point}/equalizations?include=territory&limit=200")
            added = 0
            for point in equalized:
                territory = point["relationships"]["territory"]["data"]["id"]
                if territory in have:
                    continue
                c.post("/subscriptionPrices", {"data": {
                    "type": "subscriptionPrices",
                    "attributes": {"preserveCurrentPrice": False},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sid}},
                        "territory": {"data": {"type": "territories", "id": territory}},
                        "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": point["id"]}},
                    }}})
                added += 1
            print(f"{pid}: kept {len(have)} prices, added {added} equalized")


if __name__ == "__main__":
    main()
