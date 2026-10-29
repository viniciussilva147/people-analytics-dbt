-- One row per requisition: funnel volumes, offer outcome, time to fill and the HRIS employee hired.
-- Time to fill = days from requisition opened to offer accepted.
with jobs as (
    select * from {{ ref('stg_greenhouse__jobs') }}
),

applications as (
    select * from {{ ref('stg_greenhouse__applications') }}
),

offers as (
    select o.*, a.job_id, a.candidate_id, a.application_source
    from {{ ref('stg_greenhouse__offers') }} as o
    inner join applications as a on a.application_id = o.application_id
),

funnel as (
    select
        job_id,
        count(*)                                                                         as applications,
        count(*) filter (where furthest_stage in ('phone_screen', 'onsite', 'offer'))    as reached_phone_screen,
        count(*) filter (where furthest_stage in ('onsite', 'offer'))                    as reached_onsite,
        count(*) filter (where furthest_stage = 'offer')                                 as reached_offer
    from applications
    group by job_id
),

offer_outcome as (
    select
        job_id,
        count(*)                                            as offers_extended,
        count(*) filter (where offer_status = 'accepted')   as offers_accepted,
        min(resolved_at) filter (where offer_status = 'accepted') as filled_at,
        min(start_date)  filter (where offer_status = 'accepted') as hire_start_date,
        min(candidate_id) filter (where offer_status = 'accepted') as hired_candidate_id,
        min(application_source) filter (where offer_status = 'accepted') as hired_source
    from offers
    group by job_id
),

workers as (
    select employee_id, greenhouse_candidate_id from {{ ref('stg_hris__workers') }}
    where greenhouse_candidate_id is not null
)

select
    j.job_id,
    j.job_title,
    j.department,
    j.job_status,
    j.opened_at,
    coalesce(f.applications, 0)             as applications,
    coalesce(f.reached_phone_screen, 0)     as reached_phone_screen,
    coalesce(f.reached_onsite, 0)           as reached_onsite,
    coalesce(f.reached_offer, 0)            as reached_offer,
    coalesce(o.offers_extended, 0)          as offers_extended,
    coalesce(o.offers_accepted, 0)          as offers_accepted,
    o.filled_at,
    date_diff('day', j.opened_at, o.filled_at) as days_to_fill,
    o.hire_start_date,
    o.hired_source,
    o.hired_candidate_id,
    w.employee_id                           as hired_employee_id
from jobs as j
left join funnel as f on f.job_id = j.job_id
left join offer_outcome as o on o.job_id = j.job_id
left join workers as w on w.greenhouse_candidate_id = o.hired_candidate_id
