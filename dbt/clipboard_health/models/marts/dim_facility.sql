-- One row per facility that appears in PBJ or Provider Info.
-- Name/location come from Provider Info when available, else the latest PBJ record
-- (facilities that closed may not be in the current Provider Info file).
with pbj_latest as (
    select ccn, provider_name, city, state, county_name
    from {{ ref('stg_pbj_daily') }}
    qualify row_number() over (partition by ccn order by work_date desc) = 1
),

pi as (
    select * from {{ ref('stg_provider_info') }}
)

select
    coalesce(pi.ccn, p.ccn)                         as ccn,
    coalesce(pi.provider_name, p.provider_name)     as provider_name,
    coalesce(pi.city, p.city)                       as city,
    coalesce(pi.state, p.state)                     as state,
    coalesce(pi.county, p.county_name)              as county,
    pi.zip_code,
    pi.is_urban,
    pi.ownership_type,
    pi.provider_type,
    pi.certified_beds,
    pi.chain_name,
    pi.special_focus_status,
    pi.has_abuse_icon,
    pi.overall_rating,
    pi.health_inspection_rating,
    pi.qm_rating,
    pi.staffing_rating,
    pi.nursing_staff_turnover_pct,
    pi.rn_turnover_pct,
    pi.number_of_fines,
    pi.total_fines_usd,
    pi.latitude,
    pi.longitude,
    pi.snapshot_date                                as provider_info_snapshot,
    pi.ccn is not null                              as in_provider_info
from pi
full outer join pbj_latest p on pi.ccn = p.ccn
