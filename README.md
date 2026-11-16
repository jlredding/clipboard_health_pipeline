# Nursing Home Staffing Data Pipeline (CMS PBJ → S3 → Snowflake → dbt)

<!-- TODO(Jon): one sentence in your own words on what this pipeline does and who it's for. -->

Production-style ELT pipeline behind the [Nursing Home Staffing Dashboard](https://github.com/jlredding/Clipboard_Health_Dashboard).
It replaces a one-off Colab script with scheduled, tested loads of CMS staffing and quality data
across multiple quarters.

**Architecture:** see [docs/architecture.md](docs/architecture.md) (Mermaid diagram, renders on GitHub).

## Problem
<!-- TODO(Jon): the DA project answered questions for one quarter. Why does an ops team need this automated? -->

## Data
| Source | Grain | Refresh | Rows |
|---|---|---|---|
| CMS PBJ Daily Nurse Staffing | facility × day | quarterly | ~1.3M per quarter |
| CMS Provider Information | facility | monthly | ~14,700 |

## How it works
1. **Ingest** (`ingest/ingest.py`): finds each file in the CMS catalogs (no hard-coded URLs), streams it, converts Windows-1252 to UTF-8, gzips it to S3, and writes a manifest with the source row count and checksum. Skips files already ingested.
2. **Load** (`load/load_snowflake.py`): `COPY INTO` Snowflake RAW through a storage integration. Each partition is replaced in a single transaction, so re-runs are safe. Has an internal-stage fallback.
3. **Transform** (`dbt/clipboard_health`): staging views → marts. `fct_facility_day` is incremental.
4. **Test**: 16 dbt tests, including:
   - `assert_raw_rowcount_matches_manifest`: loaded rows must equal the source file (catches truncation like the Excel 1,048,575-row cutoff)
   - `assert_q2_2024_matches_da_project`: regression test against the published dashboard numbers
   - grain, uniqueness, relationships, accepted values, source freshness
5. **Orchestrate** (`.github/workflows/pipeline.yml`): monthly schedule + manual run; every PR runs the full pipeline on DuckDB.

## Data model
| Model | Grain | Use |
|---|---|---|
| `fct_facility_day` | facility × day | daily HPRD, low-staffing days |
| `dim_facility` | facility | star ratings, ownership, beds, location |
| `mart_facility_quarter` | facility × quarter | weighted HPRD, contract share, QoQ change |
| `mart_state_quarter` | state × quarter | state comparisons |
| `mart_state_day` | state × day | trend lines |
| `snap_provider_info` | facility × version | SCD Type 2 history of ratings/ownership |

## Results
<!-- TODO(Jon): fill in after the Snowflake run. Local DuckDB run gave: -->
- Q2 2024 reconciles exactly with the dashboard: 3.30 HPRD, 34% of facilities below 3.0, 7.7% contract share
- 3.9M facility-days across 3 quarters; full local build in ~10 seconds
- Q2 2026: national HPRD up to 3.38, facilities below 3.0 down to 30%, contract share down to 5.8%

## How to run
```bash
pip install -r requirements.txt
make local                     # whole pipeline on your laptop with DuckDB
# Snowflake: run snowflake/00–02 once, fill in .env, then
set -a; source .env; set +a && make prod
```

## What I learned
<!-- TODO(Jon): 3 bullets. Ideas: why reconcile in a test; why everything lands as text in RAW;
     incremental model tradeoffs; the AssumeRole / external ID fix. -->
