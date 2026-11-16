-- Regression test against the published Data Analyst results for Q2 2024:
-- national HPRD 3.30, 34% of facilities below 3.0, 7.7% contract share.
-- If the pipeline logic drifts from the dashboard's, this fails.
{% set q = '2024Q2' %}
with fac as (
    select * from {{ ref('mart_facility_quarter') }}
    where quarter = '{{ q }}' and not is_reporting_gap
),
national as (
    select
        count(*)                                                as facilities,
        sum(nurse_hrs) / sum(resident_days)                     as hprd,
        avg(case when below_reference then 1.0 else 0.0 end)    as pct_below,
        sum(contract_hrs) / sum(nurse_hrs)                      as contract_share
    from fac
)
select * from national
where facilities > 0   -- quarter not loaded: nothing to check
  and (round(hprd, 2) <> 3.30
       or round(pct_below, 2) <> 0.34
       or round(contract_share, 3) <> 0.077)
