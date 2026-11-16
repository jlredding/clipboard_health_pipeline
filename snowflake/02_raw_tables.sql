-- RAW tables: land the files as-is (types kept loose), plus load metadata.
-- Everything lands as VARCHAR; dbt staging does the typing so a bad value never blocks a load.
-- Run once before the first load. load_duckdb.py creates the same tables locally.

use role clipboard_transformer;
use warehouse clipboard_wh;

create table if not exists clipboard_health.raw.pbj_daily (
  provnum varchar, provname varchar, city varchar, state varchar, county_name varchar,
  county_fips varchar, cy_qtr varchar, workdate varchar, mdscensus varchar,
  hrs_rndon varchar, hrs_rndon_emp varchar, hrs_rndon_ctr varchar,
  hrs_rnadmin varchar, hrs_rnadmin_emp varchar, hrs_rnadmin_ctr varchar,
  hrs_rn varchar, hrs_rn_emp varchar, hrs_rn_ctr varchar,
  hrs_lpnadmin varchar, hrs_lpnadmin_emp varchar, hrs_lpnadmin_ctr varchar,
  hrs_lpn varchar, hrs_lpn_emp varchar, hrs_lpn_ctr varchar,
  hrs_cna varchar, hrs_cna_emp varchar, hrs_cna_ctr varchar,
  hrs_natrn varchar, hrs_natrn_emp varchar, hrs_natrn_ctr varchar,
  hrs_medaide varchar, hrs_medaide_emp varchar, hrs_medaide_ctr varchar,
  _partition varchar, _source_file varchar, _loaded_at timestamp_ntz
);

create table if not exists clipboard_health.raw.provider_info (
  ccn varchar, provider_name varchar, city varchar, state varchar, zip_code varchar,
  county varchar, is_urban varchar, ownership_type varchar, provider_type varchar,
  certified_beds varchar, avg_residents_per_day varchar, chain_name varchar, chain_id varchar,
  special_focus_status varchar, abuse_icon varchar, overall_rating varchar,
  health_inspection_rating varchar, qm_rating varchar, staffing_rating varchar,
  reported_total_nurse_hprd varchar, casemix_total_nurse_hprd varchar,
  adjusted_total_nurse_hprd varchar, nursing_staff_turnover_pct varchar, rn_turnover_pct varchar,
  number_of_fines varchar, total_fines_usd varchar, latitude varchar, longitude varchar,
  processing_date varchar,
  _partition varchar, _source_file varchar, _loaded_at timestamp_ntz
);

-- one row per ingested file: what the source said it contained
create table if not exists clipboard_health.raw.load_manifest (
  dataset varchar, partition varchar, file_key varchar, source_url varchar,
  row_count number, bytes number, sha256 varchar, ingested_at timestamp_ntz,
  loaded_at timestamp_ntz
);
