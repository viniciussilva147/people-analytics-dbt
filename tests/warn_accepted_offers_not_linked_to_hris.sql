-- Data-quality monitor (warning, not a failure): accepted offers whose candidate cannot be found in the HRIS.
-- These hires exist in headcount but cannot be traced back to source, time to fill or recruiter.
{{ config(severity='warn') }}
select job_id, hired_candidate_id, hire_start_date
from {{ ref('fct_recruiting_funnel') }}
where offers_accepted = 1
  and hire_start_date <= date '{{ var("as_of_date") }}'
  and hired_employee_id is null
