-- Company-level workforce roll-forward, one row per month.
--
-- Definitions (employees only, no-shows excluded; see fct_employment_spells.is_in_workforce_metrics):
--   * Active at the end of day d: hire_date <= d and (last_day_worked is null or last_day_worked > d).
--     Someone whose last day is the last day of the month is a termination of that month and is NOT in its
--     closing headcount. With this rule the roll-forward closes exactly:
--     headcount_end = headcount_start + hires - terminations.
--   * Attrition rate = terminations in the month / average of opening and closing headcount.
--   * headcount_end_as_reported only knows terminations entered in the HRIS by month end.
--     The gap to headcount_end is the restatement caused by late-entered terminations.
with months as (
    select * from {{ ref('int_month_spine') }}
),

spells as (
    select * from {{ ref('fct_employment_spells') }}
    where is_in_workforce_metrics
),

monthly as (
    select
        m.month_start,
        m.month_end,
        count(*) filter (where s.hire_date <= m.previous_month_end
                           and (s.last_day_worked is null or s.last_day_worked > m.previous_month_end)) as headcount_start,
        count(*) filter (where s.hire_date between m.month_start and m.month_end)                      as hires,
        count(*) filter (where s.is_rehire and s.hire_date between m.month_start and m.month_end)       as rehires,
        count(*) filter (where s.last_day_worked between m.month_start and m.month_end)                as terminations,
        count(*) filter (where s.last_day_worked between m.month_start and m.month_end
                           and s.termination_type = 'voluntary')                                       as voluntary_terminations,
        count(*) filter (where s.last_day_worked between m.month_start and m.month_end
                           and s.termination_type = 'involuntary')                                     as involuntary_terminations,
        count(*) filter (where s.last_day_worked between m.month_start and m.month_end
                           and s.is_regretted)                                                         as regretted_terminations,
        count(*) filter (where s.hire_date <= m.month_end
                           and (s.last_day_worked is null or s.last_day_worked > m.month_end))         as headcount_end,
        count(*) filter (where s.hire_date <= m.month_end
                           and not (s.last_day_worked is not null
                                    and s.last_day_worked <= m.month_end
                                    and cast(s.termination_entered_at as date) <= m.month_end))        as headcount_end_as_reported
    from months as m
    cross join spells as s
    group by m.month_start, m.month_end
),

with_rates as (
    select
        *,
        (headcount_start + headcount_end) / 2.0                     as average_headcount,
        terminations / ((headcount_start + headcount_end) / 2.0)    as attrition_rate,
        voluntary_terminations / ((headcount_start + headcount_end) / 2.0) as voluntary_attrition_rate,
        headcount_end_as_reported - headcount_end                   as restatement_delta
    from monthly
)

select
    *,
    -- Trailing twelve months: sum of exits over the mean of the twelve monthly average headcounts
    case when count(*) over t12 = 12
         then sum(voluntary_terminations) over t12 / avg(average_headcount) over t12 end as voluntary_attrition_t12m,
    case when count(*) over t12 = 12
         then sum(regretted_terminations) over t12 / avg(average_headcount) over t12 end as regretted_attrition_t12m
from with_rates
window t12 as (order by month_start rows between 11 preceding and current row)
order by month_start
