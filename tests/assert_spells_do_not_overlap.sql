-- A person cannot have two employment spells at the same time (e.g. a rehire keyed before the previous exit).
select a.employee_id, a.spell_id as earlier_spell, b.spell_id as later_spell
from {{ ref('int_employment_spells') }} as a
inner join {{ ref('int_employment_spells') }} as b
    on  b.employee_id = a.employee_id
    and b.spell_number > a.spell_number
    and b.hire_date <= coalesce(a.last_day_worked, date '9999-12-31')
