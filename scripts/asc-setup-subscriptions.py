#!/usr/bin/env python3
"""Idempotently create Next Cue Pro subscriptions and one-week trials."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE_ID = "com.jackwallner.adhd"
APP_STORE_CONNECT_APP_ID = "6815023447"
GROUP_REFERENCE_NAME = "Next Cue Pro"
GROUP_DISPLAY_NAME = "Next Cue Pro"
LOCALES = ("en-US",)

# Vitals defaults: both recurring plans have a one-week free trial.
SUBSCRIPTIONS = (
    {
        "product_id": "com.jackwallner.adhd.yearly",
        "reference_name": "Next Cue Pro Yearly",
        "display_name": "Next Cue Pro Yearly",
        "description": "More routines and planning tools.",
        "period": "ONE_YEAR",
        "price": "14.99",
        "level": 1,
        "trial": True,
    },
    {
        "product_id": "com.jackwallner.adhd.monthly",
        "reference_name": "Next Cue Pro Monthly",
        "display_name": "Next Cue Pro Monthly",
        "description": "More routines and planning tools.",
        "period": "ONE_MONTH",
        "price": "1.99",
        "level": 2,
        "trial": True,
    },
)
REVIEW_NOTE = "Unlocks additional routine and planning features in Next Cue Pro."

TIERS = {
    **dict.fromkeys(("IND", "PAK", "BGD", "IDN", "VNM", "PHL", "EGY", "NGA"), (4.99, 0.69)),
    **dict.fromkeys(("TUR", "BRA", "MEX", "COL", "CHL", "THA", "MYS", "POL", "HUN", "ROU", "ZAF", "RUS"), (7.99, 0.99)),
    **dict.fromkeys(("SAU", "ARE", "CZE", "CHN"), (11.99, 1.49)),
}
FX = {
    "INR": 0.012, "PKR": 0.0036, "BDT": 0.0082, "IDR": 0.000062, "VND": 0.0000395,
    "PHP": 0.0173, "EGP": 0.020, "NGN": 0.00065, "TRY": 0.029, "BRL": 0.20,
    "MXN": 0.049, "COP": 0.00024, "CLP": 0.0011, "THB": 0.029, "MYR": 0.22,
    "PLN": 0.25, "HUF": 0.0028, "RON": 0.22, "ZAR": 0.055, "RUB": 0.011,
    "SAR": 0.27, "AED": 0.27, "CZK": 0.044, "CNY": 0.14,
}
CURRENCY_BY_TERRITORY = {
    "IND": "INR", "PAK": "PKR", "BGD": "BDT", "IDN": "IDR", "VNM": "VND", "PHL": "PHP",
    "EGY": "EGP", "NGA": "NGN", "TUR": "TRY", "BRA": "BRL", "MEX": "MXN", "COL": "COP",
    "CHL": "CLP", "THA": "THB", "MYS": "MYR", "POL": "PLN", "HUN": "HUF", "ROU": "RON",
    "ZAF": "ZAR", "RUS": "RUB", "SAU": "SAR", "ARE": "AED", "CZE": "CZK", "CHN": "CNY",
}


def require_expected_app(client: asc_lib.ASCClient) -> str:
    app = asc_lib.find_app(client, BUNDLE_ID)
    if app["id"] != APP_STORE_CONNECT_APP_ID:
        raise SystemExit(
            f"error: {BUNDLE_ID} resolved to ASC app {app['id']}, "
            f"expected {APP_STORE_CONNECT_APP_ID}"
        )
    return app["id"]


def product_metadata() -> dict:
    path = asc_lib.META / "en-US" / "products.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {}


def ensure_group(client: asc_lib.ASCClient, app_id: str) -> str:
    groups = asc_lib.list_all(client, f"/apps/{app_id}/subscriptionGroups")
    group = next(
        (item for item in groups if item["attributes"].get("referenceName") == GROUP_REFERENCE_NAME),
        None,
    )
    if group is None:
        group = client.post(
            "/subscriptionGroups",
            {
                "data": {
                    "type": "subscriptionGroups",
                    "attributes": {"referenceName": GROUP_REFERENCE_NAME},
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
        )["data"]
    group_id = group["id"]
    existing_locales = {
        item["attributes"].get("locale"): item
        for item in asc_lib.list_all(
            client, f"/subscriptionGroups/{group_id}/subscriptionGroupLocalizations"
        )
    }
    for locale in LOCALES:
        existing = existing_locales.get(locale)
        if existing:
            if existing["attributes"].get("name") != GROUP_DISPLAY_NAME:
                client.patch(
                    f"/subscriptionGroupLocalizations/{existing['id']}",
                    {
                        "data": {
                            "type": "subscriptionGroupLocalizations",
                            "id": existing["id"],
                            "attributes": {"name": GROUP_DISPLAY_NAME},
                        }
                    },
                )
            continue
        client.post(
            "/subscriptionGroupLocalizations",
            {
                "data": {
                    "type": "subscriptionGroupLocalizations",
                    "attributes": {"locale": locale, "name": GROUP_DISPLAY_NAME},
                    "relationships": {
                        "subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": group_id}}
                    },
                }
            },
        )
    return group_id


def ensure_subscription(client: asc_lib.ASCClient, group_id: str, spec: dict) -> str:
    group_subscriptions = asc_lib.list_all(client, f"/subscriptionGroups/{group_id}/subscriptions")
    other_groups = [
        group
        for group in asc_lib.list_all(
            client, f"/apps/{APP_STORE_CONNECT_APP_ID}/subscriptionGroups"
        )
        if group["id"] != group_id
    ]
    for other_group in other_groups:
        found = asc_lib.list_all(client, f"/subscriptionGroups/{other_group['id']}/subscriptions")
        if any(item["attributes"].get("productId") == spec["product_id"] for item in found):
            raise SystemExit(
                f"error: {spec['product_id']} already exists in another subscription group"
            )

    subscription = next(
        (
            item
            for item in group_subscriptions
            if item["attributes"].get("productId") == spec["product_id"]
        ),
        None,
    )
    if subscription is None:
        subscription = client.post(
            "/subscriptions",
            {
                "data": {
                    "type": "subscriptions",
                    "attributes": {
                        "name": spec["reference_name"],
                        "productId": spec["product_id"],
                        "subscriptionPeriod": spec["period"],
                        "familySharable": False,
                        "groupLevel": spec["level"],
                        "reviewNote": REVIEW_NOTE,
                    },
                    "relationships": {
                        "group": {"data": {"type": "subscriptionGroups", "id": group_id}}
                    },
                }
            },
        )["data"]
    return subscription["id"]


def ensure_localization(client: asc_lib.ASCClient, subscription_id: str, spec: dict) -> None:
    localizations = asc_lib.list_all(
        client, f"/subscriptions/{subscription_id}/subscriptionLocalizations"
    )
    by_locale = {item["attributes"].get("locale"): item for item in localizations}
    for locale in LOCALES:
        custom = product_metadata()
        prefix = "monthly" if spec["period"] == "ONE_MONTH" else "yearly"
        name = custom.get(f"{prefix}_name") or spec["display_name"]
        description = custom.get(f"{prefix}_desc") or spec["description"]
        existing = by_locale.get(locale)
        if existing:
            attrs = existing["attributes"]
            if attrs.get("name") != name or attrs.get("description") != description:
                client.patch(
                    f"/subscriptionLocalizations/{existing['id']}",
                    {
                        "data": {
                            "type": "subscriptionLocalizations",
                            "id": existing["id"],
                            "attributes": {"name": name, "description": description},
                        }
                    },
                )
            continue
        client.post(
            "/subscriptionLocalizations",
            {
                "data": {
                    "type": "subscriptionLocalizations",
                    "attributes": {"locale": locale, "name": name, "description": description},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": subscription_id}}
                    },
                }
            },
        )


def ensure_availability(client: asc_lib.ASCClient, subscription_id: str, territories: list[str]) -> None:
    try:
        availability = client.get(f"/subscriptions/{subscription_id}/subscriptionAvailability").get("data")
    except RuntimeError:
        availability = None
    if availability:
        return
    client.post(
        "/subscriptionAvailabilities",
        {
            "data": {
                "type": "subscriptionAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": subscription_id}},
                    "availableTerritories": {
                        "data": [{"type": "territories", "id": territory} for territory in territories]
                    },
                },
            }
        },
    )


def ensure_introductory_offers(client: asc_lib.ASCClient, subscription_id: str, territories: list[str]) -> None:
    offers = asc_lib.list_all(
        client,
        f"/subscriptions/{subscription_id}/introductoryOffers?include=territory&limit=200",
    )
    covered = {
        (item.get("relationships", {}).get("territory", {}).get("data") or {}).get("id")
        for item in offers
    }
    for territory in territories:
        if territory in covered:
            continue
        client.post(
            "/subscriptionIntroductoryOffers",
            {
                "data": {
                    "type": "subscriptionIntroductoryOffers",
                    "attributes": {
                        "duration": "ONE_WEEK",
                        "offerMode": "FREE_TRIAL",
                        "numberOfPeriods": 1,
                    },
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": subscription_id}},
                        "territory": {"data": {"type": "territories", "id": territory}},
                    },
                }
            },
        )


def ensure_us_price(client: asc_lib.ASCClient, subscription_id: str, amount: str) -> None:
    existing = asc_lib.list_all(
        client, f"/subscriptions/{subscription_id}/prices?filter[territory]=USA&limit=200"
    )
    if existing:
        price_ids = {
            (item.get("relationships", {}).get("subscriptionPricePoint", {}).get("data") or {}).get("id")
            for item in existing
        }
        points = asc_lib.list_all(
            client, f"/subscriptions/{subscription_id}/pricePoints?filter[territory]=USA&limit=200"
        )
        matching = {
            item["id"]
            for item in points
            if float(item["attributes"].get("customerPrice", 0)) == float(amount)
        }
        if price_ids & matching:
            return
        raise SystemExit(
            f"error: {subscription_id} already has a USA price; review it before changing to ${amount}"
        )

    points = asc_lib.list_all(
        client, f"/subscriptions/{subscription_id}/pricePoints?filter[territory]=USA&limit=200"
    )
    point = next(
        (item for item in points if float(item["attributes"].get("customerPrice", 0)) == float(amount)),
        None,
    )
    if point is None:
        raise SystemExit(f"error: USA price point ${amount} is not available")
    client.post(
        "/subscriptionPrices",
        {
            "data": {
                "type": "subscriptionPrices",
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": subscription_id}},
                    "subscriptionPricePoint": {
                        "data": {"type": "subscriptionPricePoints", "id": point["id"]}
                    },
                },
            }
        },
    )


def ensure_ppp_prices(client: asc_lib.ASCClient, subscription_id: str, index: int) -> None:
    for territory, targets in TIERS.items():
        target_usd = targets[index]
        currency = CURRENCY_BY_TERRITORY[territory]
        points = asc_lib.list_all(
            client,
            f"/subscriptions/{subscription_id}/pricePoints?filter[territory]={territory}&limit=200",
        )
        ranked = sorted(
            (
                float(point["attributes"]["customerPrice"]) * FX[currency],
                point,
            )
            for point in points
        )
        if not ranked:
            print(f"no price points for {territory}; Apple equalization will apply")
            continue
        eligible = [item for item in ranked if item[0] <= target_usd]
        _, chosen = eligible[-1] if eligible else ranked[0]
        existing = asc_lib.list_all(
            client,
            f"/subscriptions/{subscription_id}/prices?filter[territory]={territory}&limit=200",
        )
        existing_ids = {
            (item.get("relationships", {}).get("subscriptionPricePoint", {}).get("data") or {}).get("id")
            for item in existing
        }
        if chosen["id"] in existing_ids:
            continue
        if any(item.get("attributes", {}).get("manual") for item in existing):
            raise SystemExit(
                f"error: {territory} already has a different manual price for {subscription_id}; "
                "review before changing it"
            )
        client.post(
            "/subscriptionPrices",
            {
                "data": {
                    "type": "subscriptionPrices",
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": subscription_id}},
                        "territory": {"data": {"type": "territories", "id": territory}},
                        "subscriptionPricePoint": {
                            "data": {"type": "subscriptionPricePoints", "id": chosen["id"]}
                        },
                    },
                }
            },
        )
        print(
            f"set initial {territory} {spec_label(index)} price "
            f"{chosen['attributes']['customerPrice']} {currency}"
        )


def spec_label(index: int) -> str:
    return "yearly" if index == 0 else "monthly"


def main() -> None:
    client = asc_lib.ASCClient.from_credentials()
    app_id = require_expected_app(client)
    territories = [item["id"] for item in asc_lib.list_all(client, "/territories?limit=200")]
    group_id = ensure_group(client, app_id)
    for index, spec in enumerate(SUBSCRIPTIONS):
        subscription_id = ensure_subscription(client, group_id, spec)
        ensure_localization(client, subscription_id, spec)
        ensure_availability(client, subscription_id, territories)
        ensure_introductory_offers(client, subscription_id, territories)
        ensure_us_price(client, subscription_id, spec["price"])
        ensure_ppp_prices(client, subscription_id, index)
        print(f"configured {spec['product_id']} at USA ${spec['price']} with a one-week trial")


if __name__ == "__main__":
    main()
