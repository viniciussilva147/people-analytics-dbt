select
    employee_id,
    lower(trim(worker_type)) as worker_type,          -- employee | contractor
    greenhouse_candidate_id
from {{ source('hris', 'workers') }}
