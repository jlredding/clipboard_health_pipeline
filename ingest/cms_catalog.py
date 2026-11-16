"""Find CMS download URLs from the public catalogs instead of hard-coding them.

CMS changes file paths every release, so hard-coded links break. Both
catalogs below are public and need no API key.
"""
from __future__ import annotations

import requests


def quarter_start(q: str) -> str:
    """'2024Q2' -> '2024-04-01'"""
    year, n = q.upper().split("Q")
    month = {"1": "01", "2": "04", "3": "07", "4": "10"}[n]
    return f"{year}-{month}-01"


def pbj_quarter_urls(catalog_url: str, title_prefix: str, quarters: list[str]) -> dict[str, str]:
    """Return {quarter: csv_download_url} from data.cms.gov's data.json catalog."""
    catalog = requests.get(catalog_url, timeout=120).json()
    by_start: dict[str, str] = {}
    for ds in catalog["dataset"]:
        if not ds["title"].startswith(title_prefix):
            continue
        for dist in ds.get("distribution", []):
            if dist.get("format") != "CSV" or not dist.get("downloadURL"):
                continue
            for period in dist.get("temporal") or []:
                by_start[period["startDate"]] = dist["downloadURL"]

    urls, missing = {}, []
    for q in quarters:
        url = by_start.get(quarter_start(q))
        (urls.__setitem__(q, url) if url else missing.append(q))
    if missing:
        available = sorted(by_start)[-8:]
        raise LookupError(f"No PBJ file found for {missing}. Latest available start dates: {available}")
    return urls


def provider_info_url(metastore_url: str) -> tuple[str, str]:
    """Return (csv_url, snapshot_date) for the latest Provider Information file."""
    item = requests.get(metastore_url, timeout=60).json()
    csv_dist = next(d for d in item["distribution"] if d.get("downloadURL", "").lower().endswith(".csv"))
    snapshot = item.get("modified", "unknown")
    return csv_dist["downloadURL"], snapshot
