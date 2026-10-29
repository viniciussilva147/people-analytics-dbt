-- One row per employment spell, enriched with worker type, department at hire and at exit, and tenure.
-- is_in_workforce_metrics is the single switch every workforce metric uses:
-- employees only (no contractors) and no no-shows (accepted, never started).
with spells as (
    select * from {{ ref('int_employment_spells') }}
),

workers as (
    select * from {{ ref('stg_hris__workers') }}
),

jobs as (
    select * from {{ ref('int_job_history_ranges') }}
)

select
    s.spell_id,
    s.employee_id,
    w.worker_type,
    s.spell_number,
    s.is_rehire,
    s.hire_date,
    date_trunc('month', s.hire_date)                    as hire_month,
    h.department                                        as department_at_hire,
    s.last_day_worked,
    date_trunc('month', s.last_day_worked)              as termination_month,
    x.department                                        as department_at_exit,
    s.termination_type,
    s.termination_reason,
    s.is_regretted,
    s.is_no_show,
    s.termination_entered_at,
    s.days_entered_after_last_day,
    date_diff('day', s.hire_date, coalesce(s.last_day_worked, date '{{ var("as_of_date") }}')) as tenure_days,
    w.worker_type = 'employee' and not s.is_no_show     as is_in_workforce_metrics
from spells as s
inner join workers as w
    on w.employee_id = s.employee_id
left join jobs as h
    on h.employee_id = s.employee_id and s.hire_date between h.valid_from and h.valid_to
left join jobs as x
    on x.employee_id = s.employee_id and s.last_day_worked between x.valid_from and x.valid_to
