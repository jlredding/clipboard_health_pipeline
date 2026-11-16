# Local dev: whole pipeline on your Mac with DuckDB, no cloud needed
QUARTERS ?= 2024Q2 2026Q1 2026Q2

local:  ## ingest -> DuckDB -> dbt build
	python ingest/ingest.py --dest local:data/raw --quarters $(QUARTERS)
	python load/load_duckdb.py
	cd dbt/clipboard_health && DBT_PROFILES_DIR=. DBT_TARGET=dev dbt build

prod:   ## needs .env loaded: ingest -> S3 -> Snowflake -> dbt build
	python ingest/ingest.py --dest $(RAW_DEST)
	python load/load_snowflake.py --stage s3 --manifests $(RAW_DEST)
	cd dbt/clipboard_health && DBT_PROFILES_DIR=. DBT_TARGET=prod dbt build

docs:   ## dbt docs site with lineage graph
	cd dbt/clipboard_health && DBT_PROFILES_DIR=. dbt docs generate && DBT_PROFILES_DIR=. dbt docs serve
