-- Removes connector duplicates (same event landed twice) and standardizes types.
with source as (
    select * from {{ source('hris', 'employment_events') }}
),

deduplicated as (
    select *
    from source
    qualify row_number() over (partition by event_id order by _fivetran_synced desc) = 1
)

select
    event_id,
    employee_id,
    lower(trim(event_type))                         as event_type,         -- hire | rehire | termination
    cast(effective_date as date)                    as effective_date,     -- for terminations: last day worked
    lower(trim(termination_type))                   as termination_type,   -- voluntary | involuntary
    trim(termination_reason)                        as termination_reason,
    case regretted_flag when 'Y' then true when 'N' then false end as is_regretted,
    cast(entered_at as timestamp)                   as entered_at
from deduplicated
