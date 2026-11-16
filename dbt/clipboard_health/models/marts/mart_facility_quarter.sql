-- One row per facility per quarter: replaces facilities.csv from the DA project and
-- adds quality ratings and quarter-over-quarter change. HPRD is weighted
-- (total hours / total resident-days), never an average of daily ratios.
with q as (
    select
        ccn,
        quarter,
        min(state)                              as state,
        count(distinct work_date)               as days_reported,
        sum(census)                             as resident_days,
        avg(census)                             as avg_census,
        sum(nurse_hrs)                          as nurse_hrs,
        sum(rn_hrs)                             as rn_hrs,
        sum(contract_hrs)                       as contract_hrs,
        sum(is_low_day)                         as days_below_low_threshold
    from {{ ref('fct_facility_day') }}
    group by ccn, quarter
),

metrics as (
    select
        *,
        nurse_hrs / resident_days                                   as hprd,
        rn_hrs / resident_days                                      as rn_hprd,
        case when nurse_hrs > 0 then contract_hrs / nurse_hrs else 0 end as contract_share
    from q
)

select
    m.*,
    m.hprd < {{ var('hprd_reference') }}                            as below_reference,
    m.hprd < {{ var('reporting_gap_hprd') }}                        as is_reporting_gap,
    lag(m.quarter) over (partition by m.ccn order by m.quarter)     as prev_quarter,
    m.hprd - lag(m.hprd) over (partition by m.ccn order by m.quarter)                     as hprd_change,
    m.contract_share - lag(m.contract_share) over (partition by m.ccn order by m.quarter) as contract_share_change,
    f.provider_name,
    f.city,
    f.ownership_type,
    f.certified_beds,
    f.overall_rating,
    f.staffing_rating
from metrics m
left join {{ ref('dim_facility') }} f on m.ccn = f.ccn
