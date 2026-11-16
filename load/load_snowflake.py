"""
Load raw files into Snowflake RAW tables with COPY INTO.

  # main path: files already in S3, read through the external stage
  python load/load_snowflake.py --stage s3 --manifests s3://my-bucket/clipboard

  # fallback if the S3 storage integration is failing: PUT local files to an internal stage
  python load/load_snowflake.py --stage internal --manifests local:data/raw

Each partition is loaded with delete-then-COPY inside one transaction, so re-running
is safe and a failed COPY leaves the previous data in place.

Connection settings come from environment variables (see .env.example):
SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PRIVATE_KEY_PATH (key-pair auth), SNOWFLAKE_ROLE, SNOWFLAKE_WAREHOUSE
"""
from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

import snowflake.connector
from cryptography.hazmat.primitives import serialization  # installed with snowflake-connector-python

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ingest"))
from common import EXPECTED_HEADERS, check_header, local_manifests  # noqa: E402
from storage import LocalStorage, open_storage  # noqa: E402

log = logging.getLogger("load_snowflake")
DB = "clipboard_health"
STAGES = {"s3": f"{DB}.raw.cms_s3_stage", "internal": f"{DB}.raw.cms_internal_stage"}


def list_manifests(dest: str) -> list[dict]:
    store = open_storage(dest)
    if isinstance(store, LocalStorage):
        return local_manifests(store.root)
    keys = []
    paginator = store.s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=store.bucket, Prefix=store._key("_manifests/")):
        keys += [o["Key"] for o in page.get("Contents", []) if o["Key"].endswith(".json")]
    prefix = store._key("")
    return [store.read_json(k.removeprefix(prefix)) for k in sorted(keys)]


def _private_key_der() -> bytes:
    """Read the unencrypted PKCS#8 .p8 key file and return it as DER bytes for the connector."""
    path = os.path.expanduser(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"])
    with open(path, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    return key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def connect():
    # Key-pair auth: Snowflake service users (TYPE = SERVICE) can't use passwords.
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key=_private_key_der(),
        role=os.environ.get("SNOWFLAKE_ROLE", "CLIPBOARD_TRANSFORMER"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "CLIPBOARD_WH"),
        database=DB,
        schema="RAW",
    )


def load_partition(cur, m: dict, stage: str, local_root: Path | None) -> int:
    check_header(m)
    table = f"{DB}.raw.{m['dataset']}"
    cols = EXPECTED_HEADERS[m["dataset"]]
    positions = ", ".join(f"${i}" for i in range(1, len(cols) + 1))

    if local_root is not None:  # internal-stage fallback: upload first
        local_file = (local_root / m["file_key"]).resolve()
        stage_dir = str(Path(m["file_key"]).parent)
        cur.execute(f"put 'file://{local_file}' @{stage}/{stage_dir}/ auto_compress=false overwrite=true")

    cur.execute("begin")
    try:
        cur.execute(f"delete from {table} where _partition = %s", (m["partition"],))
        cur.execute(
            f"""copy into {table} ({', '.join(cols)}, _partition, _source_file, _loaded_at)
                from (select {positions}, '{m['partition']}', metadata$filename, current_timestamp()
                      from @{stage}/{m['file_key']})
                file_format = (format_name = '{DB}.raw.cms_csv_gz')
                force = true on_error = abort_statement"""
        )
        cur.execute(
            f"delete from {DB}.raw.load_manifest where dataset = %s and partition = %s", (m["dataset"], m["partition"])
        )
        cur.execute(
            f"insert into {DB}.raw.load_manifest select %s, %s, %s, %s, %s, %s, %s, %s, current_timestamp()",
            (m["dataset"], m["partition"], m["file_key"], m["source_url"], m["row_count"], m["bytes"], m["sha256"], m["ingested_at"][:19]),
        )
        cur.execute("commit")
    except Exception:
        cur.execute("rollback")
        raise
    cur.execute(f"select count(*) from {table} where _partition = %s", (m["partition"],))
    return cur.fetchone()[0]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--stage", choices=["s3", "internal"], default="s3")
    p.add_argument("--manifests", required=True, help="where ingest.py wrote: s3://bucket/prefix or local:data/raw")
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    if args.stage == "internal" and not args.manifests.startswith("local:"):
        sys.exit("--stage internal needs --manifests local:<path> (the files to PUT)")
    local_root = Path(args.manifests.removeprefix("local:")) if args.stage == "internal" else None

    manifests = list_manifests(args.manifests)
    with connect() as con, con.cursor() as cur:
        for m in manifests:
            n = load_partition(cur, m, STAGES[args.stage], local_root)
            status = "OK" if n == m["row_count"] else "MISMATCH"
            log.info("%s %s: loaded %s rows, manifest %s [%s]", m["dataset"], m["partition"], f"{n:,}", f"{m['row_count']:,}", status)


if __name__ == "__main__":
    main()
