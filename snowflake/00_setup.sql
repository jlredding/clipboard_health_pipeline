-- One-time Snowflake setup for the Clipboard Health pipeline.
-- Run as ACCOUNTADMIN (or a role with CREATE DATABASE / ROLE / WAREHOUSE).

use role accountadmin;

-- Compute: smallest size, suspends after 60s idle so it costs almost nothing
create warehouse if not exists clipboard_wh
  warehouse_size = 'XSMALL' auto_suspend = 60 auto_resume = true initially_suspended = true;

create database if not exists clipboard_health;
create schema if not exists clipboard_health.raw;       -- loaded as-is from S3, all text
create schema if not exists clipboard_health.staging;   -- dbt: typed, cleaned
create schema if not exists clipboard_health.marts;     -- dbt: what apps read
create schema if not exists clipboard_health.snapshots; -- dbt: SCD2 history

-- Roles: the pipeline writes; the dashboard and AI apps only read marts
create role if not exists clipboard_transformer;
create role if not exists clipboard_reader;
grant role clipboard_transformer to role sysadmin;
grant role clipboard_reader to role sysadmin;

grant usage on warehouse clipboard_wh to role clipboard_transformer;
grant usage on warehouse clipboard_wh to role clipboard_reader;
grant all on database clipboard_health to role clipboard_transformer;
grant all on all schemas in database clipboard_health to role clipboard_transformer;
grant all on future schemas in database clipboard_health to role clipboard_transformer;

grant usage on database clipboard_health to role clipboard_reader;
grant usage on schema clipboard_health.marts to role clipboard_reader;
grant select on all tables in schema clipboard_health.marts to role clipboard_reader;
grant select on future tables in schema clipboard_health.marts to role clipboard_reader;
grant select on all views in schema clipboard_health.marts to role clipboard_reader;
grant select on future views in schema clipboard_health.marts to role clipboard_reader;

-- Service users. Snowflake no longer lets service users sign in with a password
-- (single-factor passwords were phased out in 2026), so these use key-pair auth.
-- TODO(Jon): generate a key pair per user (commands below, run on your Mac) and paste
-- each PUBLIC key body (no BEGIN/END lines, no line breaks) into rsa_public_key.
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out pipeline_svc_key.p8 -nocrypt
--   openssl rsa -in pipeline_svc_key.p8 -pubout -out pipeline_svc_key.pub
-- Keep the .p8 private keys OUT of the repo: add *.p8 and *.pub to .gitignore.
create user if not exists pipeline_svc
  type = service
  rsa_public_key = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvBJ8sbuoYK33QQwb7xZwLGOdaBOMWHv67NQU5SVnJeya0aDLYzXTJJ7pnjaYHjJi6h5V1x3fesXNnmkCwlYAVzhFxHX6hlHlRPov0alzYapg5VaxLIw/9vSOSTylBBo+WVQxDQBSu3XxRPmsMHqdhFueggpDzlz00n0gB3iEWSxivC1JoA+w9BgHktHGhtF/E0FmtTX10xmdKRUhk4b/JHj27dy4ICINHyE5rRtwqE9Ybw3J1d3W+imVrNAVNxI1zWs3foBOZ2b5u/F0mRTsLfg8VyDtCOQZ+jfHCqCp+hNW8kDfHVYDkbqFBz6RkGzauPIfMcNfUBNCGyzsr8lcWwIDAQAB'
  default_role = clipboard_transformer default_warehouse = clipboard_wh;
grant role clipboard_transformer to user pipeline_svc;

create user if not exists app_reader_svc
  type = service
  rsa_public_key = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAq+3LhLEpvCVqMUqkWamOJFRhqVhumlASuxotLx+bDbbeoYEHdgerna60NOn2BGDC7zPrEiIEwn0QBgoT+3kuHRO11LZ9gePTjNNYgfwg7nAUHhD1Qe7d+P/4wUADp5Cf79uW3YRHD/gbs0LM1KuLqbaZP2fRE59h0+WrI4Gh507dVOerR5zAgKU5SWbaKN04KI04QVO1kaAsJ7JidZh9zSGk4MBtKJURPfOpsue68YnzF0yY59j2sh4D5hBBaPx/Cyvo5XTgnAaK0+a5sPXRSj7zA9RqaXhL7U0kQ0dgxEAUzQQWN8A+o2G9355P2EE/p/MhH2JAF+9wYzxqMU2RbwIDAQAB'
  default_role = clipboard_reader default_warehouse = clipboard_wh;
grant role clipboard_reader to user app_reader_svc;

-- Check: TYPE should be SERVICE and RSA_PUBLIC_KEY_FP should be filled in
-- desc user pipeline_svc;

-- Shared CSV format for the gzipped UTF-8 files ingest.py writes
create file format if not exists clipboard_health.raw.cms_csv_gz
  type = csv compression = gzip skip_header = 1
  field_optionally_enclosed_by = '"' empty_field_as_null = true
  null_if = ('');

-- The file format is owned by ACCOUNTADMIN, so the pipeline role needs USAGE on it
-- to create stages that reference it and to run COPY INTO with it.
grant usage on file format clipboard_health.raw.cms_csv_gz to role clipboard_transformer;
