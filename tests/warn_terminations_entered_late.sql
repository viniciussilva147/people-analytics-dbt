-- Data-quality monitor (warning): terminations keyed in the HRIS more than 30 days after the last day worked.
-- Each one makes past headcount reports wrong until they are restated (see fct_workforce_monthly.restatement_delta).
{{ config(severity='warn') }}
select spell_id, employee_id, last_day_worked, termination_entered_at, days_entered_after_last_day
from {{ ref('int_employment_spells') }}
where days_entered_after_last_day > 30
