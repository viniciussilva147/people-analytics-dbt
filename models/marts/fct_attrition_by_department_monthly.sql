-- Department-level headcount and exits, one row per month and department.
-- Headcount uses the department held on the reference date; exits use the department on the last day worked.
-- Department headcount does not roll forward on its own (internal transfers move people between departments),
-- but it must always add up to the company headcount in fct_workforce_monthly (tested).
with months as (
    select * from {{ ref('int_month_spine') }}
),

departments as (
    select distinct department from {{ ref('department_mapping') }}
),

spells as (
    select * from {{ ref('fct_employment_spells') }}
    where is_in_workforce_metrics
),

jobs as (
    select * from {{ ref('int_job_history_ranges') }}
),

headcount_end as (
    select m.month_start, j.department, count(*) as headcount_end
    from months as m
    inner join spells as s
        on s.hire_date <= m.month_end and (s.last_day_worked is null or s.last_day_worked > m.month_end)
    inner join jobs as j
        on j.employee_id = s.employee_id and m.month_end between j.valid_from and j.valid_to
    group by all
),

headcount_start as (
    select m.month_start, j.department, count(*) as headcount_start
    from months as m
    inner join spells as s
        on s.hire_date <= m.previous_month_end
       and (s.last_day_worked is null or s.last_day_worked > m.previous_month_end)
    inner join jobs as j
        on j.employee_id = s.employee_id and m.previous_month_end between j.valid_from and j.valid_to
    group by all
),

exits as (
    select
        m.month_start,
        s.department_at_exit                                            as department,
        count(*)                                                        as terminations,
        count(*) filter (where s.termination_type = 'voluntary')        as voluntary_terminations,
        count(*) filter (where s.is_regretted)                          as regretted_terminations
    from months as m
    inner join spells as s
        on s.last_day_worked between m.month_start and m.month_end
    group by all
)

select
    m.month_start,
    d.department,
    coalesce(hs.headcount_start, 0)         as headcount_start,
    coalesce(he.headcount_end, 0)           as headcount_end,
    (coalesce(hs.headcount_start, 0) + coalesce(he.headcount_end, 0)) / 2.0 as average_headcount,
    coalesce(e.terminations, 0)             as terminations,
    coalesce(e.voluntary_terminations, 0)   as voluntary_terminations,
    coalesce(e.regretted_terminations, 0)   as regretted_terminations
from months as m
cross join departments as d
left join headcount_start as hs on hs.month_start = m.month_start and hs.department = d.department
left join headcount_end   as he on he.month_start = m.month_start and he.department = d.department
left join exits           as e  on e.month_start  = m.month_start and e.department  = d.department
order by m.month_start, d.department
