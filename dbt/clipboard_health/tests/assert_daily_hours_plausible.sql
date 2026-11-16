{{ config(severity='warn') }}
-- A facility can't log negative hours, and more than 24 direct-care hours per
-- resident in a day almost always means a data-entry error. Warn, don't fail.
select ccn, work_date, census, nurse_hrs, daily_hprd
from {{ ref('fct_facility_day') }}
where nurse_hrs < 0 or daily_hprd > 24
