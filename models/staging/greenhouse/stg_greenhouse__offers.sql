select
    id                              as offer_id,
    application_id,
    lower(status)                   as offer_status,    -- accepted | rejected
    cast(sent_at as timestamp)      as sent_at,
    cast(resolved_at as timestamp)  as resolved_at,
    cast(starts_at as date)         as start_date
from {{ source('greenhouse', 'offers') }}
