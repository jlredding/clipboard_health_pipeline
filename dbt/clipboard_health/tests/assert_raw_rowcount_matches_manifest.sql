-- Every loaded partition must contain exactly the rows the source file had.
-- This is the test that would have caught the Excel 1,048,575-row truncation.
with loaded as (
    select 'pbj_daily' as dataset, _partition as partition, count(*) as loaded_rows
    from {{ source('raw', 'pbj_daily') }} group by _partition
    union all
    select 'provider_info', _partition, count(*)
    from {{ source('raw', 'provider_info') }} group by _partition
)
select m.dataset, m.partition, m.row_count as manifest_rows, l.loaded_rows
from {{ source('raw', 'load_manifest') }} m
left join loaded l on m.dataset = l.dataset and m.partition = l.partition
where l.loaded_rows is null or l.loaded_rows <> m.row_count
