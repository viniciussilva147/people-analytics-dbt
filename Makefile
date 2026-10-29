# End-to-end: synthetic raw data -> dbt models and tests -> charts and CSV exports
.PHONY: all data build report docs clean

all: data build report

data:
	python scripts/generate_data.py --db warehouse.duckdb

build:
	dbt build --profiles-dir .

report:
	python report/build_report.py

docs:
	dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .

clean:
	rm -rf warehouse.duckdb target logs exports
