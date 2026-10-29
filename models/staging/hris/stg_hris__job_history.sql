-- Maps free-text departments to the canonical list and keeps only the latest correction
-- when the same employee has more than one row for the same effective date.
with source as (
    select * from {{ source('hris', 'job_history') }}
),

mapped as (
    select
        s.row_id,
        s.employee_id,
        cast(s.effective_date as date)  as effective_date,
        s.department                    as department_raw,
        m.department,
        s.job_level,
        s.manager_id,
        lower(s.change_reason)          as change_reason,
        cast(s.entered_at as timestamp) as entered_at
    from source as s
    left join {{ ref('department_mapping') }} as m
        on m.source_system = 'hris'
       and m.raw_department = lower(trim(s.department))
)

select *
from mapped
qualify row_number() over (partition by employee_id, effective_date order by entered_at desc) = 1
