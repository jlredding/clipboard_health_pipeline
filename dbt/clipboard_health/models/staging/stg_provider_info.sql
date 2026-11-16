-- Latest Provider Information snapshot, one row per facility (CCN).
-- History across snapshots is kept by the dbt snapshot snap_provider_info.
with src as (
    select * from {{ source('raw', 'provider_info') }}
),

typed as (
    select
        ccn,
        provider_name,
        city,
        state,
        zip_code,
        county,
        {{ yn_to_bool('is_urban') }}                  as is_urban,
        ownership_type,
        provider_type,
        {{ to_int('certified_beds') }}                as certified_beds,
        {{ to_num('avg_residents_per_day') }}         as avg_residents_per_day,
        nullif(chain_name, '')                        as chain_name,
        nullif(chain_id, '')                          as chain_id,
        nullif(special_focus_status, '')              as special_focus_status,
        {{ yn_to_bool('abuse_icon') }}                as has_abuse_icon,
        {{ to_int('overall_rating') }}                as overall_rating,
        {{ to_int('health_inspection_rating') }}      as health_inspection_rating,
        {{ to_int('qm_rating') }}                     as qm_rating,
        {{ to_int('staffing_rating') }}               as staffing_rating,
        {{ to_num('reported_total_nurse_hprd') }}     as cms_reported_total_nurse_hprd,
        {{ to_num('casemix_total_nurse_hprd') }}      as cms_casemix_total_nurse_hprd,
        {{ to_num('adjusted_total_nurse_hprd') }}     as cms_adjusted_total_nurse_hprd,
        {{ to_num('nursing_staff_turnover_pct') }}    as nursing_staff_turnover_pct,
        {{ to_num('rn_turnover_pct') }}               as rn_turnover_pct,
        {{ to_int('number_of_fines') }}               as number_of_fines,
        {{ to_num('total_fines_usd') }}               as total_fines_usd,
        {{ to_num('latitude') }}                      as latitude,
        {{ to_num('longitude') }}                     as longitude,
        cast(processing_date as date)                 as snapshot_date,
        _loaded_at
    from src
)

select *
from typed
qualify row_number() over (partition by ccn order by snapshot_date desc) = 1
