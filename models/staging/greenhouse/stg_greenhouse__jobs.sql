select
    j.id                            as job_id,
    j.name                          as job_title,
    j.department_name               as department_raw,
    m.department,
    cast(j.opened_at as timestamp)  as opened_at,
    cast(j.closed_at as timestamp)  as closed_at,
    lower(j.status)                 as job_status      -- open | closed
from {{ source('greenhouse', 'jobs') }} as j
left join {{ ref('department_mapping') }} as m
    on m.source_system = 'greenhouse'
   and m.raw_department = lower(trim(j.department_name))
