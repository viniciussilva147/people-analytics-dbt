-- The last day worked can be the hire date (a no-show) but never earlier.
select spell_id, hire_date, last_day_worked
from {{ ref('int_employment_spells') }}
where last_day_worked < hire_date
