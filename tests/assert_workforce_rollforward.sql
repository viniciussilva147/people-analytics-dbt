-- Closing headcount must equal opening headcount + hires - terminations, every month,
-- and each month must open where the previous one closed.
with m as (
    select *, lag(headcount_end) over (order by month_start) as previous_headcount_end
    from {{ ref('fct_workforce_monthly') }}
)
select month_start, headcount_start, hires, terminations, headcount_end, previous_headcount_end
from m
where headcount_end != headcount_start + hires - terminations
   or (previous_headcount_end is not null and headcount_start != previous_headcount_end)
