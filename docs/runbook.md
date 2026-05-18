# Operational runbook

> If you're on-call and the `daily_elt` DAG paged, start here.

## Quick reference

| Symptom | First check | Likely cause |
|---|---|---|
| `wait_for_warehouse` hangs | `docker compose ps` postgres health | Warehouse down / OOM |
| `ingest_raw` fails | container logs `ecom-ingest` | Source schema drift |
| `dbt_seed` fails on FK | `seeds/*.csv` modified recently? | Bad seed |
| `dbt_run_*` red model | `dbt run --select <model> --debug` | SQL bug, source freshness |
| `dbt_test` red — `not_null` | `dbt test --select <test> --store-failures` | Upstream nulls leaked |
| `dbt_test` red — `relationships` | run failures table | Orphan FKs from incomplete load |
| `assert_order_totals_match_items` fails | check loader log | Loader rounding regression |

## Common operations

### 1. Manually re-run today's pipeline

```bash
make trigger-dag
# or, single-shot from host:
make seed && make dbt-build
```

### 2. Recover from a failed dbt run

```bash
# Find the failing model
docker compose --profile tools run --rm dbt build --fail-fast --target dev

# Inspect compiled SQL
cat dbt/target/compiled/ecommerce_analytics/models/.../<model>.sql

# Re-run only the failed model and its descendants
docker compose --profile tools run --rm dbt build --select <model>+ --target dev
```

### 3. Investigate a failed test

```bash
# Persist test failures into the warehouse for SQL inspection
docker compose --profile tools run --rm dbt test \
  --select <test_name> --store-failures --target dev

# Then query the audit schema:
psql -c "select * from dbt_test_audit.<test_name> limit 100;"
```

### 4. Schema drift in `raw.*`

If ingestion adds a new column:
1. Update `sql/init/02_create_raw_tables.sql` (so fresh installs work).
2. Apply migration on existing warehouse: `ALTER TABLE raw.<t> ADD COLUMN ...`.
3. Update the relevant `stg_*.sql` to surface or ignore the new column.
4. Update `models/staging/_sources.yml` column docs/tests.
5. Re-run `dbt build`.

### 5. Reset everything (destructive)

```bash
make clean   # tears down containers AND wipes Postgres + Airflow volumes
make up
make airflow-init
make seed
make dbt-build
```

### 6. Promote dev → prod (Snowflake)

1. Ensure `.env` has `SNOWFLAKE_*` populated.
2. `DBT_PROFILE_TARGET=prod make dbt-build` (or set in Airflow Variable).
3. CI runs `dbt build --target ci` against an ephemeral postgres on every PR;
   manual approval gate triggers prod build.

## Credential rotation

| Credential | Where it lives | Rotation steps |
|---|---|---|
| `POSTGRES_PASSWORD` | `.env` | update `.env`, `docker compose up -d postgres airflow-scheduler airflow-webserver` |
| `SNOWFLAKE_PASSWORD` | `.env` (or secret manager in prod) | rotate in Snowflake, update env, redeploy DAGs |
| `AIRFLOW_ADMIN_PASSWORD` | `.env`, set on first init | `airflow users delete` then `airflow users create` |

In production these all live in AWS Secrets Manager / GCP Secret Manager and are
mounted into the Airflow workers.

## SLAs

| Metric | Target |
|---|---|
| `daily_elt` DAG completion | by 08:30 UTC (90 min after start) |
| dbt source freshness `raw.orders` | warn at 24h, error at 48h |
| Test pass rate | 100% — any failure pages |

## Escalation

1. PagerDuty: `data-platform-oncall`
2. Slack: `#data-incidents`
3. Backup: `data-platform-lead`
