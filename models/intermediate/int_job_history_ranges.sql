-- Turns effective-dated job rows into validity ranges, so any date can be joined to the job held on that date.
select
    employee_id,
    department,
    job_level,
    manager_id,
    change_reason,
    effective_date as valid_from,
    coalesce(
        cast(lead(effective_date) over (partition by employee_id order by effective_date) - interval 1 day as date),
        date '9999-12-31'
    ) as valid_to
from {{ ref('stg_hris__job_history') }}
