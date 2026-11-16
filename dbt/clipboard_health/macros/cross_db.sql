{# Small cross-database helpers so the same models run on DuckDB (dev/CI) and Snowflake (prod). #}

{% macro parse_yyyymmdd(col) -%}
    {{ return(adapter.dispatch('parse_yyyymmdd')(col)) }}
{%- endmacro %}

{% macro default__parse_yyyymmdd(col) -%}
    try_to_date({{ col }}, 'YYYYMMDD')
{%- endmacro %}

{% macro duckdb__parse_yyyymmdd(col) -%}
    try_strptime({{ col }}, '%Y%m%d')::date
{%- endmacro %}

{# text -> number; blank or junk becomes null instead of failing the run #}
{% macro to_num(col) -%}
    try_cast(nullif(trim({{ col }}), '') as double)
{%- endmacro %}

{% macro to_int(col) -%}
    try_cast(nullif(trim({{ col }}), '') as integer)
{%- endmacro %}

{# 'Y'/'N' -> boolean #}
{% macro yn_to_bool(col) -%}
    case upper(trim({{ col }})) when 'Y' then true when 'N' then false end
{%- endmacro %}
