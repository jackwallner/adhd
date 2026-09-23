#!/usr/bin/env python3
"""Idempotently create the Next Cue Pro lifetime in-app purchase."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE_ID = "com.jackwallner.adhd"
APP_STORE_CONNECT_APP_ID = "6815023447"
PRODUCT_ID = "com.jackwallner.adhd.lifetime"
REFERENCE_NAME = "Next Cue Pro Lifetime"
DISPLAY_NAME = "Next Cue Pro Lifetime"
DESCRIPTION = "Unlock Next Cue Pro for life."
PRICE = "29.99"
LOCALE = "en-US"
V1_API = "https://api.appstoreconnect.apple.com/v1"
V2_API = "https://api.appstoreconnect.apple.com/v2"



def use_v2(client: asc_lib.ASCClient, operation):
    previous_api = asc_lib.API
    asc_lib.API = V2_API
    try:
        return operation()
    finally:
        asc_lib.API = previous_api


def use_v1(client: asc_lib.ASCClient, operation):
    previous_api = asc_lib.API
    asc_lib.API = V1_API
    try:
        return operation()
    finally:
        asc_lib.API = previous_api


def find_app(client: asc_lib.ASCClient) -> dict:
    app = asc_lib.find_app(client, BUNDLE_ID)
    if app["id"] != APP_STORE_CONNECT_APP_ID:
        raise SystemExit(
            f"error: {BUNDLE_ID} resolved to ASC app {app['id']}, "
            f"expected {APP_STORE_CONNECT_APP_ID}"
        )
    return app


def localized_product() -> tuple[str, str]:
    path = asc_lib.META / LOCALE / "products.json"
    values = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    return values.get("lifetime_name", DISPLAY_NAME), values.get("lifetime_desc", DESCRIPTION)


def ensure_product(client: asc_lib.ASCClient, app_id: str) -> str:
    products = asc_lib.list_all(client, f"/apps/{app_id}/inAppPurchasesV2")
    product = next(
        (item for item in products if item["attributes"].get("productId") == PRODUCT_ID),
        None,
    )
    if product:
        return product["id"]

    def create() -> dict:
        return client.post(
            "/inAppPurchases",
            {
                "data": {
                    "type": "inAppPurchases",
                    "attributes": {
                        "name": REFERENCE_NAME,
                        "productId": PRODUCT_ID,
                        "inAppPurchaseType": "NON_CONSUMABLE",
                        "reviewNote": "A one-time purchase for additional Next Cue Pro features.",
                    },
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
        )["data"]

    return use_v2(client, create)["id"]


def ensure_localization(client: asc_lib.ASCClient, product_id: str) -> None:
    localizations = use_v2(
        client,
        lambda: asc_lib.list_all(
            client, f"/inAppPurchases/{product_id}/inAppPurchaseLocalizations"
        ),
    )
    name, description = localized_product()
    existing = next(
        (item for item in localizations if item["attributes"].get("locale") == LOCALE),
        None,
    )
    if existing:
        attrs = existing["attributes"]
        if attrs.get("name") == name and attrs.get("description") == description:
            return
        use_v2(
            client,
            lambda: client.patch(
                f"/inAppPurchaseLocalizations/{existing['id']}",
                {
                    "data": {
                        "type": "inAppPurchaseLocalizations",
                        "id": existing["id"],
                        "attributes": {"name": name, "description": description},
                    }
                },
            ),
        )
        return
    use_v2(
        client,
        lambda: client.post(
            "/inAppPurchaseLocalizations",
            {
                "data": {
                    "type": "inAppPurchaseLocalizations",
                    "attributes": {"locale": LOCALE, "name": name, "description": description},
                    "relationships": {
                        "inAppPurchaseV2": {
                            "data": {"type": "inAppPurchases", "id": product_id}
                        }
                    },
                }
            },
        ),
    )


def ensure_availability(client: asc_lib.ASCClient, product_id: str, territories: list[str]) -> None:
    try:
        availability = use_v2(
            client,
            lambda: client.get(f"/inAppPurchases/{product_id}/inAppPurchaseAvailability").get("data"),
        )
    except RuntimeError:
        availability = None
    if availability:
        return
    use_v2(
        client,
        lambda: client.post(
            "/inAppPurchaseAvailabilities",
            {
                "data": {
                    "type": "inAppPurchaseAvailabilities",
                    "attributes": {"availableInNewTerritories": True},
                    "relationships": {
                        "inAppPurchase": {"data": {"type": "inAppPurchases", "id": product_id}},
                        "availableTerritories": {
                            "data": [{"type": "territories", "id": territory} for territory in territories]
                        },
                    },
                }
            },
        ),
    )


def ensure_price_schedule(client: asc_lib.ASCClient, product_id: str) -> None:
    try:
        schedule = use_v2(
            client,
            lambda: client.get(f"/inAppPurchases/{product_id}/iapPriceSchedule").get("data"),
        )
    except RuntimeError:
        schedule = None
    if schedule:
        print("lifetime price schedule already exists; leaving it unchanged")
        return

    usa_points = use_v2(
        client,
        lambda: asc_lib.list_all(
            client,
            f"/inAppPurchases/{product_id}/pricePoints?filter[territory]=USA&limit=200",
        ),
    )
    usa_point = next(
        (
            point
            for point in usa_points
            if float(point["attributes"].get("customerPrice", 0)) == float(PRICE)
        ),
        None,
    )
    if usa_point is None:
        raise SystemExit(f"error: USA lifetime price point ${PRICE} is not available")
    ref = {"type": "inAppPurchasePrices", "id": "${usa}"}
    included = {
        "type": "inAppPurchasePrices",
        "id": "${usa}",
        "attributes": {"startDate": None},
        "relationships": {
            "inAppPurchasePricePoint": {
                "data": {
                    "type": "inAppPurchasePricePoints",
                    "id": usa_point["id"],
                }
            }
        },
    }
    use_v1(
        client,
        lambda: client.post(
            "/inAppPurchasePriceSchedules",
            {
                "data": {
                    "type": "inAppPurchasePriceSchedules",
                    "relationships": {
                        "inAppPurchase": {
                            "data": {"type": "inAppPurchases", "id": product_id}
                        },
                        "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                        "manualPrices": {"data": [ref]},
                    },
                },
                "included": [included],
            },
        ),
    )
    print("lifetime USA base set; Apple will equalize other territories")


def main() -> None:
    client = asc_lib.ASCClient.from_credentials()
    app = find_app(client)
    territories = [item["id"] for item in asc_lib.list_all(client, "/territories?limit=200")]
    product_id = ensure_product(client, app["id"])
    ensure_localization(client, product_id)
    ensure_availability(client, product_id, territories)
    ensure_price_schedule(client, product_id)
    print(f"configured {PRODUCT_ID} at USA ${PRICE}")


if __name__ == "__main__":
    main()
