# Architecture

## Goals & non-goals

**Goals**
- Single-command bring-up of an end-to-end ELT stack on a laptop.
- Realistic, internally-consistent synthetic data so dashboards look real.
- Production patterns: layered modeling, tests, snapshots, docs, CI, lineage.
- Cloud-portable: swap Postgres → Snowflake or Airflow → MWAA via env vars.

**Non-goals**
- Real-time streaming (this is batch ELT).
- Cost optimization (everything runs on a single host).
- Auth / RBAC beyond a basic `bi_reader` Postgres role.

## High-level data flow

```
 Source system (synthetic)         raw schema           dbt staging         dbt intermediate          dbt marts
 ┌────────────────────────┐    ┌────────────────┐    ┌─────────────┐    ┌───────────────────┐    ┌──────────────────┐
 │  Faker generator       │ ─▶ │  raw.customers │ ─▶ │ stg_customer│ ─▶ │ int_orders_       │ ─▶ │ mart_core.       │
 │  (deterministic, seed) │    │  raw.orders    │    │ stg_orders  │    │ enriched          │    │   dim_customers  │
 │                        │    │  raw.products  │    │ stg_products│    │ int_session_funnel│    │   dim_products   │
 │  load_to_postgres.py   │    │  raw.payments  │    │ stg_payments│    │ int_customer_     │    │   fct_orders     │
 │  (truncate+insert)     │    │  raw.web_*     │    │ stg_web_*   │    │ first_order       │    │   fct_order_items│
 └────────────────────────┘    └────────────────┘    └─────────────┘    └───────────────────┘    │ mart_finance.*   │
                                                                                                  │ mart_marketing.* │
                                                                                                  └──────────────────┘
                                                              ▲
                                                              │
                                                       ┌─────────────┐
                                                       │ snapshots/  │   SCD2 history
                                                       │ snap_products│
                                                       │ snap_customers│
                                                       └─────────────┘
```

## Layered modeling rationale

| Layer | Materialization | Purpose |
|---|---|---|
| `raw` | external (loaded by Python) | Source-of-truth landing, append-friendly |
| `staging` | view | 1:1 with sources, type-cast and renamed; cheap to recompute |
| `intermediate` | ephemeral | Reusable joined CTEs; never persisted, not exposed to BI |
| `marts.core` | table | Conformed dims + base facts shared across business areas |
| `marts.finance` | table | Revenue, margin, payments — owned by Finance |
| `marts.marketing` | table | Cohorts, RFM, funnel, attribution — owned by Marketing |

Why ephemeral for intermediate? They serve as building blocks for marts and don't
need to be queried directly. This keeps the warehouse footprint small.

## Entity-relationship diagram

```
                  ┌────────────────┐
                  │  dim_customers │
                  │ (customer_id)  │
                  └───────┬────────┘
                          │ 1
                          │
                          │ N
        ┌─────────────────▼─────────────────┐
        │             fct_orders             │
        │  (order_id, customer_id,           │
        │   gross_revenue, gross_margin,     │
        │   customer_order_type, ...)        │
        └─────────────────┬─────────────────┘
                          │ 1
                          │
                          │ N
        ┌─────────────────▼─────────────────┐         ┌──────────────────┐
        │           fct_order_items          │ ── N─1 │   dim_products   │
        │  (order_item_id, order_id,         │        │  (product_id,    │
        │   product_id, quantity, line_*)    │        │   sku, category) │
        └────────────────────────────────────┘        └──────────────────┘

                  fct_funnel_daily ◀── int_session_funnel ◀── stg_web_sessions ▶─ stg_web_events
                  fct_customer_cohorts ◀── int_customer_first_order
                  dim_customers_rfm ◀── dim_customers + fct_orders
                  fct_channel_attribution ◀── purchase events × sessions × orders
```

## Architectural decisions

### ADR-001: Postgres as the local warehouse
- **Context:** Need a warehouse that runs in Docker on a laptop.
- **Decision:** Postgres 15. Compatible enough with Snowflake SQL for swap.
- **Consequence:** Some Snowflake-specific functions need wrapping in macros.

### ADR-002: dbt-core (not dbt Cloud)
- **Context:** Open source / portable. CI must run dbt builds.
- **Decision:** `dbt-core` driven by Airflow `BashOperator`s.
- **Alternatives considered:** dbt Cloud, Cosmos (Astronomer's dbt-Airflow lib).
- **Future:** swap `BashOperator` for Cosmos to get task-per-model parallelism.

### ADR-003: Truncate-and-load for raw layer
- **Context:** Synthetic generator regenerates the full dataset each run.
- **Decision:** TRUNCATE + bulk INSERT inside one transaction.
- **Production swap:** replace ingestion with Airbyte / Fivetran / CDC into the
  same `raw.*` tables. Downstream models don't change.

### ADR-004: Tests as the deployment gate
- **Decision:** `dbt build` runs models *and* tests; failure aborts the DAG.
- **Test classes used:** generic (unique/not_null/relationships/accepted_values),
  `dbt_expectations` (range/regex/value-set), and singular tests for cross-model
  invariants (totals reconciliation, funnel monotonicity, no-future-orders).

## Lineage & docs

`dbt docs generate && dbt docs serve` produces a browsable site with:
- Model-level descriptions (from `_models.yml`)
- Column-level descriptions and tests
- Source freshness
- DAG visualisation

In CI, `target/manifest.json` and `target/catalog.json` are uploaded as artifacts
so the docs can be hosted via GitHub Pages from the artifact tarball.

## Cloud swap matrix

| Component | Local | Cloud equivalent | What changes |
|---|---|---|---|
| Warehouse | Postgres | Snowflake / BigQuery / Redshift | `DBT_PROFILE_TARGET=prod`, set Snowflake env vars |
| Ingestion | Python loader | Airbyte / Fivetran / Meltano | Replace the `ingest` container; preserve `raw.*` schema |
| Orchestration | Airflow LocalExecutor | MWAA / Cloud Composer / Astronomer | Same DAG file; deploy via CI |
| BI | Metabase (h2-backed) | Looker / Tableau / Superset | New BI tool points at marts |
| CI | GitHub Actions | same | unchanged |
