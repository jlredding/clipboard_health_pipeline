"""Shared by both loaders: read manifests and check for schema drift."""
from __future__ import annotations

import json
from pathlib import Path

# Raw table columns, in file order (load metadata columns are added by the loaders)
EXPECTED_HEADERS = {
    "pbj_daily": [
        "provnum", "provname", "city", "state", "county_name", "county_fips", "cy_qtr", "workdate", "mdscensus",
        "hrs_rndon", "hrs_rndon_emp", "hrs_rndon_ctr", "hrs_rnadmin", "hrs_rnadmin_emp", "hrs_rnadmin_ctr",
        "hrs_rn", "hrs_rn_emp", "hrs_rn_ctr", "hrs_lpnadmin", "hrs_lpnadmin_emp", "hrs_lpnadmin_ctr",
        "hrs_lpn", "hrs_lpn_emp", "hrs_lpn_ctr", "hrs_cna", "hrs_cna_emp", "hrs_cna_ctr",
        "hrs_natrn", "hrs_natrn_emp", "hrs_natrn_ctr", "hrs_medaide", "hrs_medaide_emp", "hrs_medaide_ctr",
    ],
    "provider_info": [
        "ccn", "provider_name", "city", "state", "zip_code", "county", "is_urban", "ownership_type", "provider_type",
        "certified_beds", "avg_residents_per_day", "chain_name", "chain_id", "special_focus_status", "abuse_icon",
        "overall_rating", "health_inspection_rating", "qm_rating", "staffing_rating", "reported_total_nurse_hprd",
        "casemix_total_nurse_hprd", "adjusted_total_nurse_hprd", "nursing_staff_turnover_pct", "rn_turnover_pct",
        "number_of_fines", "total_fines_usd", "latitude", "longitude", "processing_date",
    ],
}


class SchemaDriftError(RuntimeError):
    pass


def check_header(manifest: dict) -> None:
    """Positional loads are only safe if CMS hasn't added, dropped or reordered columns."""
    expected = EXPECTED_HEADERS[manifest["dataset"]]
    got = manifest.get("header")
    if got != expected:
        added = sorted(set(got or []) - set(expected))
        dropped = sorted(set(expected) - set(got or []))
        raise SchemaDriftError(
            f"{manifest['dataset']} {manifest['partition']}: header changed. added={added} dropped={dropped}. "
            "Update EXPECTED_HEADERS, the raw table DDL and stg models before loading."
        )


def local_manifests(raw_root: Path) -> list[dict]:
    return [json.loads(p.read_text()) for p in sorted((raw_root / "_manifests").rglob("*.json"))]
