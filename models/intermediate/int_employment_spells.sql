-- One row per continuous period of employment (spell). A rehired person has one spell per stint.
-- Each hire/rehire is paired with the first termination on or after it and before the next hire.
with events as (
    select * from {{ ref('stg_hris__employment_events') }}
),

starts as (
    select
        employee_id,
        event_id                    as start_event_id,
        event_type = 'rehire'       as is_rehire,
        effective_date              as hire_date,
        lead(effective_date) over (partition by employee_id order by effective_date) as next_hire_date
    from events
    where event_type in ('hire', 'rehire')
),

terminations as (
    select
        employee_id,
        event_id                    as termination_event_id,
        effective_date              as last_day_worked,
        termination_type,
        termination_reason,
        is_regretted,
        entered_at                  as termination_entered_at
    from events
    where event_type = 'termination'
),

paired as (
    select
        s.*,
        t.termination_event_id,
        t.last_day_worked,
        t.termination_type,
        t.termination_reason,
        t.is_regretted,
        t.termination_entered_at
    from starts as s
    left join terminations as t
        on  t.employee_id = s.employee_id
        and t.last_day_worked >= s.hire_date
        and (s.next_hire_date is null or t.last_day_worked < s.next_hire_date)
)

select
    employee_id || '-' || cast(row_number() over (partition by employee_id order by hire_date) as varchar) as spell_id,
    employee_id,
    row_number() over (partition by employee_id order by hire_date) as spell_number,
    start_event_id,
    is_rehire,
    hire_date,
    termination_event_id,
    last_day_worked,
    termination_type,
    termination_reason,
    is_regretted,
    termination_entered_at,
    coalesce(termination_reason = 'No Show', false)                       as is_no_show,
    date_diff('day', last_day_worked, cast(termination_entered_at as date)) as days_entered_after_last_day
from paired
