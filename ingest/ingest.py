"""
Ingest CMS nursing-home data into the raw zone (S3 or a local folder).

For each source partition (one PBJ quarter, or one Provider Info snapshot):
  1. find the download URL in the CMS catalog
  2. skip it if the raw zone already has it from the same URL (idempotent)
  3. stream the CSV, transcode to UTF-8, gzip it, and count rows
  4. write the file plus a JSON manifest (row count, checksum, source URL)

The manifest is what dbt later reconciles against, so a truncated load
(the Excel 1,048,575-row problem from the DA project) fails a test instead
of silently shipping.

Usage:
  python ingest/ingest.py --dest local:data/raw            # local dev
  python ingest/ingest.py --dest s3://my-bucket/clipboard   # AWS
  python ingest/ingest.py --dest s3://... --only pbj --quarters 2024Q2
"""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import logging
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import requests
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cms_catalog import pbj_quarter_urls, provider_info_url  # noqa: E402
from storage import open_storage  # noqa: E402

log = logging.getLogger("ingest")
ROOT = Path(__file__).resolve().parents[1]

# Provider Info has 100+ columns with spaces and slashes in the names.
# Keep the ones the marts and AI apps use, renamed to snake_case.
PROVIDER_COLUMNS = {
    "CMS Certification Number (CCN)": "ccn",
    "Provider Name": "provider_name",
    "City/Town": "city",
    "State": "state",
    "ZIP Code": "zip_code",
    "County/Parish": "county",
    "Urban": "is_urban",
    "Ownership Type": "ownership_type",
    "Provider Type": "provider_type",
    "Number of Certified Beds": "certified_beds",
    "Average Number of Residents per Day": "avg_residents_per_day",
    "Chain Name": "chain_name",
    "Chain ID": "chain_id",
    "Special Focus Status": "special_focus_status",
    "Abuse Icon": "abuse_icon",
    "Overall Rating": "overall_rating",
    "Health Inspection Rating": "health_inspection_rating",
    "QM Rating": "qm_rating",
    "Staffing Rating": "staffing_rating",
    "Reported Total Nurse Staffing Hours per Resident per Day": "reported_total_nurse_hprd",
    "Case-Mix Total Nurse Staffing Hours per Resident per Day": "casemix_total_nurse_hprd",
    "Adjusted Total Nurse Staffing Hours per Resident per Day": "adjusted_total_nurse_hprd",
    "Total nursing staff turnover": "nursing_staff_turnover_pct",
    "Registered Nurse turnover": "rn_turnover_pct",
    "Number of Fines": "number_of_fines",
    "Total Amount of Fines in Dollars": "total_fines_usd",
    "Latitude": "latitude",
    "Longitude": "longitude",
    "Processing Date": "processing_date",
}


def stream_to_gzip(url: str, encoding: str, out_path: Path, keep: dict[str, str] | None = None) -> dict:
    """Download url, transcode to UTF-8, optionally select/rename columns, gzip to out_path.

    Returns row count (data rows, header excluded), byte size and sha256 of the gzip.
    Counting with the csv module (not line counts) handles quoted newlines correctly.
    """
    rows = 0
    with requests.get(url, stream=True, timeout=120) as resp:
        resp.raise_for_status()
        resp.raw.decode_content = True
        resp.raw.auto_close = False  # let TextIOWrapper hit EOF cleanly instead of reading a closed stream
        text = io.TextIOWrapper(resp.raw, encoding=encoding, newline="")
        reader = csv.reader(text)
        header = next(reader)
        with gzip.open(out_path, "wt", encoding="utf-8", newline="") as gz:
            writer = csv.writer(gz, quoting=csv.QUOTE_MINIMAL)
            if keep:
                missing = [c for c in keep if c not in header]
                if missing:
                    raise ValueError(f"Source is missing expected columns: {missing}")
                idx = [header.index(c) for c in keep]
                writer.writerow(keep.values())
                for row in reader:
                    writer.writerow([row[i] for i in idx])
                    rows += 1
            else:
                writer.writerow(header)
                for row in reader:
                    writer.writerow(row)
                    rows += 1
    data = out_path.read_bytes()
    out_header = list(keep.values()) if keep else [h.lower() for h in header]
    return {"row_count": rows, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "header": out_header}


def ingest_one(store, dataset: str, partition: str, url: str, encoding: str, keep=None, force=False) -> dict:
    file_key = f"{dataset}/{partition}/{dataset}.csv.gz"
    manifest_key = f"_manifests/{dataset}/{partition.replace('=', '_')}.json"

    existing = store.read_json(manifest_key)
    if existing and existing.get("source_url") == url and not force:
        log.info("skip %s %s (already ingested, %s rows)", dataset, partition, f"{existing['row_count']:,}")
        return existing

    log.info("download %s %s", dataset, partition)
    with tempfile.TemporaryDirectory() as tmp:
        local = Path(tmp) / "data.csv.gz"
        stats = stream_to_gzip(url, encoding, local, keep)
        store.put_file(local, file_key)

    manifest = {
        "dataset": dataset,
        "partition": partition,
        "file_key": file_key,
        "source_url": url,
        "ingested_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        **stats,
    }
    store.write_json(manifest_key, manifest)
    log.info("wrote %s (%s rows, %.1f MB gz)", file_key, f"{stats['row_count']:,}", stats["bytes"] / 1e6)
    return manifest


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dest", required=True, help="s3://bucket/prefix or local:path")
    p.add_argument("--only", choices=["pbj", "provider"], help="ingest just one source")
    p.add_argument("--quarters", nargs="*", help="override quarters in config/sources.yml, e.g. 2024Q2")
    p.add_argument("--force", action="store_true", help="re-download even if already ingested")
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    cfg = yaml.safe_load((ROOT / "config" / "sources.yml").read_text())
    store = open_storage(args.dest)
    results = []

    if args.only in (None, "pbj"):
        pbj = cfg["pbj_daily_nurse_staffing"]
        quarters = args.quarters or pbj["quarters"]
        urls = pbj_quarter_urls(pbj["catalog_url"], pbj["title_prefix"], quarters)
        for q in quarters:
            results.append(ingest_one(store, "pbj_daily", f"quarter={q}", urls[q], pbj["source_encoding"], force=args.force))

    if args.only in (None, "provider"):
        pi = cfg["provider_info"]
        url, snapshot = provider_info_url(pi["metastore_url"])
        results.append(ingest_one(store, "provider_info", f"snapshot={snapshot}", url, pi["source_encoding"], keep=PROVIDER_COLUMNS, force=args.force))

    total = sum(r["row_count"] for r in results)
    log.info("done: %d partitions, %s rows in raw zone", len(results), f"{total:,}")


if __name__ == "__main__":
    main()
