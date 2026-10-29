-- Department headcount must add up to company headcount every month.
-- A gap means someone active had no job record on that date (a hole in the effective-dated history).
with by_department as (
    select month_start, sum(headcount_end) as headcount_end
    from {{ ref('fct_attrition_by_department_monthly') }}
    group by month_start
)
select c.month_start, c.headcount_end as company, d.headcount_end as sum_of_departments
from {{ ref('fct_workforce_monthly') }} as c
inner join by_department as d using (month_start)
where c.headcount_end != d.headcount_end
