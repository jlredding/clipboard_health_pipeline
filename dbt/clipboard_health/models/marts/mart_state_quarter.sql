-- One row per state per quarter. Excludes reporting-gap facilities, matching the
-- dashboard default in the DA project.
select
    state,
    quarter,
    count(*)                                                    as facilities,
    sum(nurse_hrs) / sum(resident_days)                         as hprd,
    avg(case when below_reference then 1.0 else 0.0 end)        as pct_facilities_below_reference,
    sum(contract_hrs) / nullif(sum(nurse_hrs), 0)               as contract_share,
    avg(case when contract_hrs = 0 then 1.0 else 0.0 end)       as pct_facilities_no_contract,
    sum(case when days_below_low_threshold >= 10 then 1 else 0 end) as watchlist_facilities
from {{ ref('mart_facility_quarter') }}
where not is_reporting_gap
group by state, quarter
