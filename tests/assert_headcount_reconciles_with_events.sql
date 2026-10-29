-- Independent recount of the closing headcount straight from the raw events (no spells, no marts):
-- an employee is active at the end of the as-of date when their latest event on or before it is a hire
-- or rehire. On the same day a termination sorts after a hire, so no-shows count as inactive.
with latest_event as (
    select e.employee_id, e.event_type
    from {{ ref('stg_hris__employment_events') }} as e
    inner join {{ ref('stg_hris__workers') }} as w
        on w.employee_id = e.employee_id and w.worker_type = 'employee'
    where e.effective_date <= date '{{ var("as_of_date") }}'
    qualify row_number() over (
        partition by e.employee_id
        order by e.effective_date desc, case when e.event_type = 'termination' then 1 else 0 end desc
    ) = 1
),

independent as (
    select count(*) as headcount from latest_event where event_type in ('hire', 'rehire')
),

mart as (
    select headcount_end as headcount
    from {{ ref('fct_workforce_monthly') }}
    where month_end = date '{{ var("as_of_date") }}'
)

select independent.headcount as from_events, mart.headcount as from_mart
from independent cross join mart
where independent.headcount != mart.headcount
