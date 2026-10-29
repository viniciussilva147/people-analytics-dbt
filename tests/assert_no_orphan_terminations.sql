-- Every termination must close a spell. An orphan means a termination with no hire before it.
select e.event_id, e.employee_id, e.effective_date
from {{ ref('stg_hris__employment_events') }} as e
left join {{ ref('int_employment_spells') }} as s
    on s.termination_event_id = e.event_id
where e.event_type = 'termination'
  and s.spell_id is null
