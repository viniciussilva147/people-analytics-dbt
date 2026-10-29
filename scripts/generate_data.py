"""
Generate synthetic HRIS (Dayforce-like) and ATS (Greenhouse-like) raw tables into DuckDB.

The raw schemas imitate what an ELT tool such as Fivetran would land in a warehouse.
Known data-quality issues are injected on purpose. The script prints how many of each
it injected, so the dbt tests and marts can be checked against expected numbers.

Usage: python scripts/generate_data.py [--db warehouse.duckdb] [--seed 42]
"""
import argparse
from dataclasses import dataclass, field

import duckdb
import numpy as np
import pandas as pd

START, AS_OF = pd.Timestamp("2023-01-01"), pd.Timestamp("2025-12-31")

DEPT_WEIGHTS = {"Engineering": .30, "Sales": .22, "Customer Success": .20,
                "Marketing": .10, "Finance": .08, "People": .10}
# Monthly voluntary exit hazard by department (first-year employees get a multiplier)
VOL_HAZARD = {"Engineering": .011, "Sales": .022, "Customer Success": .020,
              "Marketing": .014, "Finance": .009, "People": .012}
FIRST_YEAR_MULT, INVOL_HAZARD = 1.8, .004

# The HRIS has inconsistent free-text department names; the ATS uses its own taxonomy
HRIS_VARIANTS = {"Engineering": ["Engineering", "engineering", "Engineering "],
                 "Sales": ["Sales", "SALES"],
                 "Customer Success": ["Customer Success", "Cust. Success", "customer success "],
                 "Marketing": ["Marketing"],
                 "Finance": ["Finance", "Finance & Accounting"],
                 "People": ["People", "People & Culture", "HR"]}
ATS_NAMES = {"Engineering": "R&D - Engineering", "Sales": "Go-To-Market - Sales",
             "Customer Success": "Go-To-Market - Customer Success", "Marketing": "Go-To-Market - Marketing",
             "Finance": "G&A - Finance", "People": "G&A - People"}

VOL_REASONS = ["Better Opportunity", "Compensation", "Career Growth", "Relocation", "Personal"]
INVOL_REASONS = ["Performance", "Restructuring", "Policy Violation"]
SOURCES, SOURCE_P = ["LinkedIn", "Career Site", "Referral", "Job Board", "Agency"], [.35, .25, .15, .15, .10]


@dataclass
class Person:
    employee_id: str
    worker_type: str
    dept: str
    level: int
    candidate_id: str | None = None
    active: bool = True
    hire_month: pd.Timestamp | None = None
    rehire_on: pd.Timestamp | None = None
    events: list = field(default_factory=list)


def main(db_path: str, seed: int) -> None:
    rng = np.random.default_rng(seed)
    depts = list(DEPT_WEIGHTS)
    pick_dept = lambda: rng.choice(depts, p=list(DEPT_WEIGHTS.values()))  # noqa: E731
    injected = {k: 0 for k in ["rehires", "no_shows", "late_terminations_over_30d", "duplicate_event_rows",
                               "job_history_corrections", "contractors", "hires_without_ats_link",
                               "declined_offers", "open_requisitions", "internal_transfers"]}

    people: dict[str, Person] = {}
    events, job_history, jobs, applications, offers = [], [], [], [], []
    ids = {"emp": 0, "evt": 0, "jh": 0, "job": 0, "app": 0, "cand": 0, "offer": 0}

    def next_id(kind, prefix, width=6):
        ids[kind] += 1
        return f"{prefix}{ids[kind]:0{width}d}"

    def add_event(p, event_type, eff, entered=None, **kw):
        events.append(dict(event_id=next_id("evt", "EV"), employee_id=p.employee_id, event_type=event_type,
                           effective_date=eff.date(), termination_type=kw.get("ttype"),
                           termination_reason=kw.get("reason"), regretted_flag=kw.get("regretted"),
                           entered_at=(entered or eff + pd.Timedelta(hours=int(rng.integers(8, 72))))))

    def add_job_row(p, eff, reason):
        variant = rng.choice(HRIS_VARIANTS[p.dept])
        managers = [q.employee_id for q in people.values() if q.active and q.dept == p.dept and q is not p]
        manager = rng.choice(managers) if managers and rng.random() > .02 else None
        row = dict(row_id=next_id("jh", "JH"), employee_id=p.employee_id, effective_date=eff.date(),
                   department=variant, job_level=f"L{p.level}", manager_id=manager, change_reason=reason,
                   entered_at=eff + pd.Timedelta(hours=int(rng.integers(1, 48))))
        if rng.random() < .03:  # wrong department keyed first, corrected later with the same effective date
            wrong = rng.choice([d for d in depts if d != p.dept])
            job_history.append({**row, "row_id": next_id("jh", "JH"), "department": HRIS_VARIANTS[wrong][0],
                                "entered_at": row["entered_at"] - pd.Timedelta(days=2)})
            injected["job_history_corrections"] += 1
        job_history.append(row)

    def new_person(dept, worker_type):
        p = Person(next_id("emp", "E", 5), worker_type, dept, int(rng.choice([1, 2, 3, 4, 5], p=[.3, .3, .2, .15, .05])))
        people[p.employee_id] = p
        injected["contractors"] += worker_type == "contractor"
        return p

    def recruit(dept, start_date):
        """Requisition, applicants and offers in the ATS for one hire starting on start_date."""
        job_id = next_id("job", "J", 5)
        opened = start_date - pd.Timedelta(days=int(rng.integers(35, 120)))
        accepted_at = start_date - pd.Timedelta(days=int(rng.integers(14, 35)))
        n_apps = int(rng.integers(15, 60))
        app_rows = []
        for _ in range(n_apps):
            cand = next_id("cand", "C", 6)
            applied = opened + pd.Timedelta(days=int(rng.integers(0, max(1, (accepted_at - opened).days - 7))))
            stage = rng.choice(["application_review", "phone_screen", "onsite"], p=[.62, .25, .13])
            app_rows.append(dict(id=next_id("app", "A", 7), candidate_id=cand, job_id=job_id, applied_at=applied,
                                 source=rng.choice(SOURCES, p=SOURCE_P), current_stage=stage, status="rejected",
                                 rejected_at=applied + pd.Timedelta(days=int(rng.integers(3, 30)))))
        if rng.random() < .15:  # first choice declined the offer
            app_rows[-2].update(current_stage="offer", status="rejected", rejected_at=accepted_at - pd.Timedelta(days=5))
            offers.append(dict(id=next_id("offer", "O", 6), application_id=app_rows[-2]["id"], status="rejected",
                               sent_at=accepted_at - pd.Timedelta(days=12), resolved_at=accepted_at - pd.Timedelta(days=5),
                               starts_at=None))
            injected["declined_offers"] += 1
        hired = app_rows[-1]
        hired.update(current_stage="offer", status="hired", rejected_at=None)
        offers.append(dict(id=next_id("offer", "O", 6), application_id=hired["id"], status="accepted",
                           sent_at=accepted_at - pd.Timedelta(days=4), resolved_at=accepted_at,
                           starts_at=start_date.date()))
        applications.extend(app_rows)
        jobs.append(dict(id=job_id, name=f"{dept} Specialist", department_name=ATS_NAMES[dept],
                         opened_at=opened, closed_at=accepted_at, status="closed"))
        return hired["candidate_id"]

    # Workforce on the first day of the window (hired before the window starts)
    for _ in range(450):
        p = new_person(pick_dept(), "contractor" if rng.random() < .08 else "employee")
        hire = START - pd.Timedelta(days=int(rng.integers(20, 2900)))
        p.hire_month = hire
        add_event(p, "Hire", hire)
        add_job_row(p, hire, "Hire")

    for month_start in pd.date_range(START, AS_OF, freq="MS"):
        month_end = month_start + pd.offsets.MonthEnd(0)
        days = (month_end - month_start).days + 1
        rand_day = lambda: month_start + pd.Timedelta(days=int(rng.integers(0, days)))  # noqa: E731

        # Rehires due this month
        for p in [q for q in people.values() if q.rehire_on is not None and q.rehire_on <= month_end]:
            p.active, p.rehire_on, p.hire_month = True, None, p.rehire_on
            p.dept = pick_dept() if rng.random() < .3 else p.dept
            add_event(p, "Rehire", p.hire_month)
            add_job_row(p, p.hire_month, "Rehire")
            injected["rehires"] += 1

        # Exits, transfers and promotions among people active this month
        for p in [q for q in people.values() if q.active and q.hire_month < month_start]:
            tenure_m = (month_start - p.hire_month).days / 30.4
            vol = VOL_HAZARD[p.dept] * (FIRST_YEAR_MULT if tenure_m < 12 else 1)
            u = rng.random()
            if u < vol + INVOL_HAZARD:
                voluntary = u < vol
                last_day = rand_day()
                late = rng.random() < .10
                entered = last_day + pd.Timedelta(days=int(rng.integers(31, 75)) if late else int(rng.integers(-5, 3)))
                injected["late_terminations_over_30d"] += late
                regretted = ("Y" if rng.random() < .25 + .1 * p.level else "N") if voluntary else None
                add_event(p, "Termination", last_day, entered=entered,
                          ttype="Voluntary" if voluntary else "Involuntary",
                          reason=rng.choice(VOL_REASONS if voluntary else INVOL_REASONS), regretted=regretted)
                p.active = False
                if voluntary and p.worker_type == "employee" and rng.random() < .06:
                    p.rehire_on = last_day + pd.Timedelta(days=int(rng.integers(90, 360)))
                continue
            if rng.random() < .005:
                p.dept = rng.choice([d for d in depts if d != p.dept])
                add_job_row(p, rand_day(), "Transfer")
                injected["internal_transfers"] += 1
            elif rng.random() < .012 and p.level < 6:
                p.level += 1
                add_job_row(p, rand_day(), "Promotion")

        # New hires (through the ATS, except most contractors)
        for _ in range(rng.poisson(14)):
            dept = pick_dept()
            is_contractor = rng.random() < .08
            p = new_person(dept, "contractor" if is_contractor else "employee")
            start_date = rand_day()
            p.hire_month = start_date
            if not is_contractor:
                cand = recruit(dept, start_date)
                if rng.random() < .05:
                    injected["hires_without_ats_link"] += 1
                else:
                    p.candidate_id = cand
            add_event(p, "Hire", start_date)
            add_job_row(p, start_date, "Hire")
            if not is_contractor and rng.random() < .01:  # accepted, never showed up
                add_event(p, "Termination", start_date, ttype="Voluntary", reason="No Show", regretted="N")
                p.active = False
                injected["no_shows"] += 1

    # Requisitions still open on the as-of date
    for _ in range(25):
        dept = pick_dept()
        opened = AS_OF - pd.Timedelta(days=int(rng.integers(5, 70)))
        job_id = next_id("job", "J", 5)
        jobs.append(dict(id=job_id, name=f"{dept} Specialist", department_name=ATS_NAMES[dept],
                         opened_at=opened, closed_at=None, status="open"))
        for _ in range(int(rng.integers(3, 25))):
            applied = opened + pd.Timedelta(days=int(rng.integers(0, max(1, (AS_OF - opened).days))))
            applications.append(dict(id=next_id("app", "A", 7), candidate_id=next_id("cand", "C", 6), job_id=job_id,
                                     applied_at=applied, source=rng.choice(SOURCES, p=SOURCE_P),
                                     current_stage=rng.choice(["application_review", "phone_screen"], p=[.8, .2]),
                                     status="active", rejected_at=None))
        injected["open_requisitions"] += 1

    # Exact duplicate rows from the connector (same event, synced twice)
    synced = pd.Timestamp("2026-01-02 03:00")
    ev = pd.DataFrame(events)
    ev["_fivetran_synced"] = synced
    dup = ev.sample(frac=.015, random_state=seed).assign(_fivetran_synced=synced + pd.Timedelta(hours=6))
    injected["duplicate_event_rows"] = len(dup)
    ev = pd.concat([ev, dup], ignore_index=True)

    workers = pd.DataFrame([dict(employee_id=p.employee_id, worker_type=p.worker_type.title(),
                                 greenhouse_candidate_id=p.candidate_id) for p in people.values()])

    con = duckdb.connect(db_path)
    for schema in ("raw_hris", "raw_greenhouse"):
        con.execute(f"create schema if not exists {schema}")
    tables = {"raw_hris.workers": workers, "raw_hris.employment_events": ev,
              "raw_hris.job_history": pd.DataFrame(job_history), "raw_greenhouse.jobs": pd.DataFrame(jobs),
              "raw_greenhouse.applications": pd.DataFrame(applications), "raw_greenhouse.offers": pd.DataFrame(offers)}
    for name, df in tables.items():
        con.register("df_tmp", df)
        con.execute(f"create or replace table {name} as select * from df_tmp")
        con.unregister("df_tmp")
    con.close()

    print(f"Wrote raw tables to {db_path}:")
    for name, df in tables.items():
        print(f"  {name:<32} {len(df):>7,} rows")
    print("\nInjected on purpose (check dbt tests and marts against these):")
    for k, v in injected.items():
        print(f"  {k:<28} {v:>5}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="warehouse.duckdb")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    main(args.db, args.seed)
