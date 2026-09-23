#!/usr/bin/env python3
"""Fill the App Store Connect fields fastlane deliver does not create for a first version.

Sets the age rating questionnaire, categories, copyright, content rights, and the
App Review contact on the editable version. The review phone comes from
ASC_REVIEW_PHONE so it never lives in this repository.
"""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A

BUNDLE_ID = "com.jackwallner.adhd"
META = Path(__file__).resolve().parent.parent / "fastlane" / "metadata" / "en-US"

AGE_RATING = {
    "advertising": False, "gambling": False, "healthOrWellnessTopics": False,
    "lootBox": False, "messagingAndChat": False, "parentalControls": False,
    "ageAssurance": False, "unrestrictedWebAccess": False, "userGeneratedContent": False,
    **{key: "NONE" for key in (
        "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated",
        "gunsOrOtherWeapons", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
        "sexualContentGraphicAndNudity", "sexualContentOrNudity", "horrorOrFearThemes",
        "matureOrSuggestiveThemes", "violenceCartoonOrFantasy",
        "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic")},
}

REVIEW_NOTES = (
    "Next Cue is a routine planner. No account or login is needed. "
    "Create a routine from a template on first launch, then tap Start routine to step through it. "
    "The first routine is free. Adding a second routine opens the Next Cue Pro paywall "
    "(monthly and yearly subscriptions with a one-week free trial, plus a lifetime purchase). "
    "Restore purchases, Privacy Policy, Terms, and the Apple Standard EULA are linked on the paywall and in Settings. "
    "The app is an organization tool and does not diagnose, treat, or give medical advice."
)


def meta(field: str) -> str:
    return (META / f"{field}.txt").read_text().strip()


def main() -> None:
    phone = os.environ.get("ASC_REVIEW_PHONE")
    if not phone:
        raise SystemExit("error: set ASC_REVIEW_PHONE")
    c = A.ASCClient.from_credentials()
    app = A.find_app(c, BUNDLE_ID)
    version = A.find_editable_version(c, app["id"])
    info = A.find_editable_app_info(c, app["id"])

    decl = c.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    c.patch(f"/ageRatingDeclarations/{decl['id']}", {"data": {
        "type": "ageRatingDeclarations", "id": decl["id"], "attributes": AGE_RATING}})
    print("age rating set")

    c.patch(f"/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": meta("primary_category")}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": meta("secondary_category")}},
    }}})
    print("categories set")

    c.patch(f"/apps/{app['id']}", {"data": {"type": "apps", "id": app["id"], "attributes": {
        "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    c.patch(f"/appStoreVersions/{version['id']}", {"data": {
        "type": "appStoreVersions", "id": version["id"],
        "attributes": {"copyright": meta("copyright"), "releaseType": "MANUAL"}}})
    print("copyright, content rights, manual release set")

    review = {
        "contactFirstName": "Jack", "contactLastName": "Wallner",
        "contactEmail": "jackwallner@gmail.com", "contactPhone": phone,
        "demoAccountRequired": False, "notes": REVIEW_NOTES,
    }
    existing = c.get(f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    if existing:
        c.patch(f"/appStoreReviewDetails/{existing['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": existing["id"], "attributes": review}})
    else:
        c.post("/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": review,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})
    print("review contact set")


if __name__ == "__main__":
    main()
