"""
Load the local raw zone into DuckDB (local dev + CI). Same RAW tables as Snowflake,
so the dbt models run unchanged against either target.

  python load/load_duckdb.py --raw data/raw --db data/clipboard_health.duckdb
"""
from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

import duckdb

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import EXPECTED_HEADERS, check_header, local_manifests  # noqa: E402

log = logging.getLogger("load_duckdb")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--raw", default="data/raw")
    p.add_argument("--db", default="data/clipboard_health.duckdb")
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    raw_root = Path(args.raw)
    con = duckdb.connect(args.db)
    con.execute("create schema if not exists raw")
    con.execute("""create table if not exists raw.load_manifest (
        dataset varchar, partition varchar, file_key varchar, source_url varchar, row_count bigint,
        bytes bigint, sha256 varchar, ingested_at timestamp, loaded_at timestamp)""")

    for m in local_manifests(raw_root):
        check_header(m)
        table = f"raw.{m['dataset']}"
        cols = EXPECTED_HEADERS[m["dataset"]]
        path = (raw_root / m["file_key"]).as_posix()
        # everything lands as text; dbt staging does the typing (same as Snowflake RAW)
        types = ", ".join(f"'{c}': 'VARCHAR'" for c in cols)
        select = f"""select *, '{m['partition']}' as _partition, '{m['file_key']}' as _source_file,
                     current_timestamp::timestamp as _loaded_at
                     from read_csv('{path}', header=true, columns={{{types}}}, quote='"', escape='"', strict_mode=true)"""
        exists = con.execute(
            "select count(*) from information_schema.tables where table_schema='raw' and table_name=?", [m["dataset"]]
        ).fetchone()[0]
        if not exists:
            con.execute(f"create table {table} as {select} limit 0")
        # idempotent: replace the partition, never append twice
        con.execute(f"delete from {table} where _partition = ?", [m["partition"]])
        con.execute(f"insert into {table} {select}")
        con.execute("delete from raw.load_manifest where dataset = ? and partition = ?", [m["dataset"], m["partition"]])
        con.execute(
            "insert into raw.load_manifest values (?, ?, ?, ?, ?, ?, ?, ?, current_timestamp)",
            [m["dataset"], m["partition"], m["file_key"], m["source_url"], m["row_count"], m["bytes"], m["sha256"], m["ingested_at"][:19]],
        )
        loaded = con.execute(f"select count(*) from {table} where _partition = ?", [m["partition"]]).fetchone()[0]
        log.info("%s %s: %s rows (manifest %s)", table, m["partition"], f"{loaded:,}", f"{m['row_count']:,}")
    con.close()


if __name__ == "__main__":
    main()
