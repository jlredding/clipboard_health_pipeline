-- One row per state per day, for trend lines. Replaces daily_state.csv.
select
    d.state,
    d.work_date,
    d.quarter,
    count(*)                                    as facilities_reporting,
    sum(d.census)                               as residents,
    sum(d.nurse_hrs) / sum(d.census)            as hprd,
    sum(d.contract_hrs) / nullif(sum(d.nurse_hrs), 0) as contract_share
from {{ ref('fct_facility_day') }} d
join {{ ref('mart_facility_quarter') }} q
  on d.ccn = q.ccn and d.quarter = q.quarter and not q.is_reporting_gap
group by d.state, d.work_date, d.quarter
