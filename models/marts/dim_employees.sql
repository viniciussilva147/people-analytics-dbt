-- One row per worker, with status and job as of the reporting date (var as_of_date).
-- Former workers carry the job they held on their last day.
with workers as (
    select * from {{ ref('stg_hris__workers') }}
),

spells as (
    select * from {{ ref('int_employment_spells') }}
),

spell_summary as (
    select
        employee_id,
        min(hire_date)  as first_hire_date,
        count(*)        as spell_count
    from spells
    group by employee_id
),

latest_spell as (
    select *
    from spells
    qualify row_number() over (partition by employee_id order by hire_date desc) = 1
),

status as (
    select
        employee_id,
        hire_date                       as latest_hire_date,
        last_day_worked                 as latest_last_day_worked,
        is_no_show,
        last_day_worked is null
            or last_day_worked > date '{{ var("as_of_date") }}' as is_active_as_of_date,
        least(date '{{ var("as_of_date") }}', coalesce(last_day_worked, date '{{ var("as_of_date") }}')) as job_reference_date
    from latest_spell
),

jobs as (
    select * from {{ ref('int_job_history_ranges') }}
)

select
    w.employee_id,
    w.worker_type,
    w.greenhouse_candidate_id is not null   as is_linked_to_ats,
    ss.first_hire_date,
    st.latest_hire_date,
    st.latest_last_day_worked,
    ss.spell_count,
    ss.spell_count > 1                      as has_been_rehired,
    st.is_no_show,
    st.is_active_as_of_date,
    j.department                            as current_department,
    j.job_level                             as current_job_level,
    j.manager_id                            as current_manager_id
from workers as w
inner join spell_summary as ss on ss.employee_id = w.employee_id
inner join status as st on st.employee_id = w.employee_id
left join jobs as j
    on j.employee_id = w.employee_id
   and st.job_reference_date between j.valid_from and j.valid_to
