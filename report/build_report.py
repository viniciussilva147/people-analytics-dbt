"""
Build the charts used in the README from the dbt marts, print a KPI summary and export the marts to CSV
(ready to upload to Hex, Sigma or any BI tool).

Usage: python report/build_report.py [--db warehouse.duckdb]
"""
import argparse
from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import matplotlib.ticker as mtick  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
IMG, EXPORTS = ROOT / "docs" / "img", ROOT / "exports"
BLUE, GREY, INK, MUTED = "#2a78d6", "#9a9994", "#0b0b0b", "#52514e"
MARTS = ["fct_workforce_monthly", "fct_attrition_by_department_monthly", "fct_recruiting_funnel",
         "fct_employment_spells", "dim_employees"]

plt.rcParams.update({
    "figure.facecolor": "white", "axes.facecolor": "white", "savefig.dpi": 150, "font.size": 10,
    "axes.spines.top": False, "axes.spines.right": False, "axes.edgecolor": "#bdbcb7",
    "axes.grid": True, "axes.axisbelow": True, "grid.color": "#e6e6e3", "grid.linewidth": .8,
    "axes.labelcolor": MUTED, "xtick.color": MUTED, "ytick.color": MUTED, "legend.frameon": False,
    "axes.titlesize": 12, "axes.titleweight": "bold", "axes.titlelocation": "left",
})


def save(fig, name):
    IMG.mkdir(parents=True, exist_ok=True)
    fig.savefig(IMG / name, bbox_inches="tight")
    plt.close(fig)


def main(db_path):
    con = duckdb.connect(db_path, read_only=True)
    wf = con.execute("select * from marts.fct_workforce_monthly order by month_start").df()
    dept = con.execute("""
        select department,
               sum(voluntary_terminations) / avg(average_headcount) as voluntary_rate,
               sum(regretted_terminations) / avg(average_headcount) as regretted_rate
        from marts.fct_attrition_by_department_monthly
        where month_start > (select max(month_start) from marts.fct_attrition_by_department_monthly) - interval 12 month
        group by department order by voluntary_rate
    """).df()
    rec = con.execute("""
        select department, median(days_to_fill) as median_days_to_fill,
               sum(offers_accepted) / sum(offers_extended) as offer_acceptance
        from marts.fct_recruiting_funnel where offers_accepted = 1
        group by department order by median_days_to_fill
    """).df()

    # 1. Headcount
    fig, ax = plt.subplots(figsize=(8, 3.6))
    ax.plot(wf.month_start, wf.headcount_end, color=BLUE, lw=2)
    ax.set_title("Month-end headcount (employees)")
    ax.set_ylim(0, wf.headcount_end.max() * 1.15)
    last = wf.iloc[-1]
    ax.annotate(f"{last.headcount_end:,}", (last.month_start, last.headcount_end), xytext=(6, 0),
                textcoords="offset points", va="center", color=INK, fontweight="bold")
    save(fig, "headcount.png")

    # 2. Trailing twelve-month attrition
    t12 = wf.dropna(subset=["voluntary_attrition_t12m"])
    fig, ax = plt.subplots(figsize=(8, 3.6))
    for col, label, color, ls in [("voluntary_attrition_t12m", "Voluntary", BLUE, "-"),
                                  ("regretted_attrition_t12m", "Regretted", GREY, "--")]:
        ax.plot(t12.month_start, t12[col], color=color, lw=2, ls=ls, label=label)
        ax.annotate(f"{label} {t12[col].iloc[-1]:.0%}", (t12.month_start.iloc[-1], t12[col].iloc[-1]),
                    xytext=(6, 0), textcoords="offset points", va="center", color=INK, fontsize=9)
    ax.yaxis.set_major_formatter(mtick.PercentFormatter(1, decimals=0))
    ax.set_ylim(0, t12.voluntary_attrition_t12m.max() * 1.25)
    ax.set_title("Trailing twelve-month attrition rate")
    ax.legend(loc="lower left")
    save(fig, "attrition_t12m.png")

    # 3. Voluntary attrition by department, last twelve months
    fig, ax = plt.subplots(figsize=(8, 3.6))
    ax.barh(dept.department, dept.voluntary_rate, color=BLUE, height=.55)
    for y, v in enumerate(dept.voluntary_rate):
        ax.annotate(f"{v:.0%}", (v, y), xytext=(4, 0), textcoords="offset points", va="center", fontsize=9)
    ax.xaxis.set_major_formatter(mtick.PercentFormatter(1, decimals=0))
    ax.grid(axis="y", visible=False)
    ax.set_title("Voluntary attrition by department, last 12 months")
    save(fig, "attrition_by_department.png")

    # 4. Restatement caused by late-entered terminations
    fig, ax = plt.subplots(figsize=(8, 3.2))
    ax.bar(wf.month_start, wf.restatement_delta, width=20, color=GREY)
    ax.yaxis.set_major_locator(mtick.MaxNLocator(integer=True))
    ax.set_title("Headcount overstated at month end because exits were keyed late")
    ax.set_ylabel("people")
    save(fig, "restatement.png")

    # 5. Time to fill by department
    fig, ax = plt.subplots(figsize=(8, 3.6))
    ax.barh(rec.department, rec.median_days_to_fill, color=BLUE, height=.55)
    for y, v in enumerate(rec.median_days_to_fill):
        ax.annotate(f"{v:.0f} days", (v, y), xytext=(4, 0), textcoords="offset points", va="center", fontsize=9)
    ax.grid(axis="y", visible=False)
    ax.set_title("Median days to fill (requisition opened to offer accepted)")
    save(fig, "time_to_fill.png")

    # Exports for BI tools
    EXPORTS.mkdir(exist_ok=True)
    for mart in MARTS:
        con.execute(f"copy (select * from marts.{mart}) to '{EXPORTS / (mart + '.csv')}' (header, delimiter ',')")

    filled = con.execute("""select count(*), median(days_to_fill), sum(offers_accepted)/sum(offers_extended)
                            from marts.fct_recruiting_funnel where offers_accepted = 1""").fetchone()
    print(f"As of {last.month_end:%Y-%m-%d}")
    print(f"  Headcount (employees)            {last.headcount_end:,}")
    print(f"  Voluntary attrition, T12M        {last.voluntary_attrition_t12m:.1%}")
    print(f"  Regretted attrition, T12M        {last.regretted_attrition_t12m:.1%}")
    print(f"  Highest voluntary attrition      {dept.iloc[-1].department} ({dept.iloc[-1].voluntary_rate:.0%})")
    print(f"  Requisitions filled              {filled[0]:,}")
    print(f"  Median days to fill              {filled[1]:.0f}")
    print(f"  Offer acceptance rate            {filled[2]:.0%}")
    print(f"  Max month-end restatement        {wf.restatement_delta.max()} people")
    print(f"Charts in {IMG.relative_to(ROOT)}/, CSV exports in {EXPORTS.relative_to(ROOT)}/")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(ROOT / "warehouse.duckdb"))
    main(ap.parse_args().db)
