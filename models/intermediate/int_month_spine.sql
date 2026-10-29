-- One row per calendar month in the reporting window.
select
    cast(month_start as date)                                  as month_start,
    cast(month_start + interval 1 month - interval 1 day as date) as month_end,
    cast(month_start - interval 1 day as date)                 as previous_month_end
from range(
    date '{{ var("start_date") }}',
    date '{{ var("as_of_date") }}' + interval 1 day,
    interval 1 month
) as t(month_start)
