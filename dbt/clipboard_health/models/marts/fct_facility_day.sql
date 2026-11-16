{{ config(
    materialized='incremental',
    unique_key=['ccn', 'work_date'],
    incremental_strategy='delete+insert',
    on_schema_change='append_new_columns'
) }}

-- One row per facility per day with residents present (zero-census days dropped,
-- as in the DA project). Incremental: only re-processes rows loaded since the last run,
-- so adding a new quarter doesn't rebuild the whole history.
select
    ccn,
    work_date,
    quarter,
    state,
    census,
    rn_hrs,
    lpn_hrs,
    cna_hrs,
    nurse_hrs,
    contract_hrs,
    rn_contract_hrs,
    rn_don_hrs,
    nurse_hrs / census                                              as daily_hprd,
    rn_hrs / census                                                 as daily_rn_hprd,
    case when nurse_hrs / census < {{ var('low_day_hprd') }} then 1 else 0 end as is_low_day,
    _loaded_at
from {{ ref('stg_pbj_daily') }}
where census > 0
{% if is_incremental() %}
  and _loaded_at > (select max(_loaded_at) from {{ this }})
{% endif %}
