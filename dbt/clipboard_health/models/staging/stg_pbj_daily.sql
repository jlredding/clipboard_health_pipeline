-- Typed, cleaned PBJ daily staffing. One row per facility per day, all days kept;
-- filters that change meaning (zero-census days) happen in the marts, not here.
with src as (
    select * from {{ source('raw', 'pbj_daily') }}
),

typed as (
    select
        provnum                                   as ccn,
        provname                                  as provider_name,
        city,
        state,
        county_name,
        county_fips,
        cy_qtr                                    as quarter,
        {{ parse_yyyymmdd('workdate') }}          as work_date,
        {{ to_int('mdscensus') }}                 as census,

        -- Director of Nursing: cap at 24h/day (bad entries over 24 found in the DA project)
        least({{ to_num('hrs_rndon') }}, 24)      as rn_don_hrs,
        {{ to_num('hrs_rnadmin') }}               as rn_admin_hrs,
        {{ to_num('hrs_lpnadmin') }}              as lpn_admin_hrs,

        -- Direct-care hours: these three make up HPRD
        {{ to_num('hrs_rn') }}                    as rn_hrs,
        {{ to_num('hrs_rn_ctr') }}                as rn_contract_hrs,
        {{ to_num('hrs_lpn') }}                   as lpn_hrs,
        {{ to_num('hrs_lpn_ctr') }}               as lpn_contract_hrs,
        {{ to_num('hrs_cna') }}                   as cna_hrs,
        {{ to_num('hrs_cna_ctr') }}               as cna_contract_hrs,

        {{ to_num('hrs_natrn') }}                 as na_trainee_hrs,
        {{ to_num('hrs_medaide') }}               as med_aide_hrs,

        _partition,
        _loaded_at
    from src
)

select
    *,
    coalesce(rn_hrs, 0) + coalesce(lpn_hrs, 0) + coalesce(cna_hrs, 0)                            as nurse_hrs,
    coalesce(rn_contract_hrs, 0) + coalesce(lpn_contract_hrs, 0) + coalesce(cna_contract_hrs, 0) as contract_hrs
from typed
