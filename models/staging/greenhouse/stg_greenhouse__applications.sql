select
    id                              as application_id,
    candidate_id,
    job_id,
    cast(applied_at as timestamp)   as applied_at,
    source                          as application_source,
    lower(current_stage)            as furthest_stage,  -- application_review | phone_screen | onsite | offer
    lower(status)                   as application_status,
    cast(rejected_at as timestamp)  as rejected_at
from {{ source('greenhouse', 'applications') }}
