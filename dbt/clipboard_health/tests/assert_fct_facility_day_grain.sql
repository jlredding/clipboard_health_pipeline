-- One row per facility per day
select ccn, work_date, count(*) as n
from {{ ref('fct_facility_day') }}
group by ccn, work_date
having count(*) > 1
