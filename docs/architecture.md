# Architecture

```mermaid
flowchart LR
    subgraph CMS["CMS public data"]
        A1[data.json catalog<br/>PBJ daily staffing, quarterly]
        A2[Provider Data Catalog<br/>Provider Info, monthly]
    end
    subgraph Ingest["ingest/ingest.py"]
        B[find URLs → stream → cp1252→UTF-8<br/>→ gzip → count rows → manifest]
    end
    subgraph S3["AWS S3 raw zone"]
        C1[pbj_daily/quarter=YYYYQn/]
        C2[provider_info/snapshot=DATE/]
        C3[_manifests/*.json]
    end
    subgraph SF["Snowflake: CLIPBOARD_HEALTH"]
        D[RAW<br/>COPY INTO via storage integration]
        E[STAGING<br/>dbt views: typed, cleaned]
        F[MARTS<br/>fct_facility_day, dim_facility,<br/>mart_facility_quarter, mart_state_*]
        G[SNAPSHOTS<br/>snap_provider_info SCD2]
    end
    subgraph Use["Consumers (read-only role)"]
        H1[Streamlit dashboard]
        H2[AI assistant + monitor agent]
    end
    A1 & A2 --> B --> C1 & C2 & C3
    C1 & C2 & C3 --> D --> E --> F --> H1 & H2
    E --> G
    GH[GitHub Actions<br/>monthly + manual; PR CI on DuckDB] -.orchestrates.-> B & D & E
```

**Dev vs prod.** The same dbt models run on DuckDB (`DBT_TARGET=dev`, local and in PR CI) and on
Snowflake (`DBT_TARGET=prod`). Three small macros in `macros/cross_db.sql` cover the dialect differences.
