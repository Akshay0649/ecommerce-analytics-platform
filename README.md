# E-commerce Analytics Platform

[![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)](.github/workflows/ci.yml)
[![dbt](https://img.shields.io/badge/dbt-1.7-FF694B?logo=dbt&logoColor=white)](https://www.getdbt.com/)
[![Airflow](https://img.shields.io/badge/Airflow-2.9-017CEE?logo=apacheairflow&logoColor=white)](https://airflow.apache.org/)
[![Postgres](https://img.shields.io/badge/Postgres-15-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> A production-grade, end-to-end data engineering platform that turns raw
> e-commerce OLTP records into a Kimball-style analytics layer powering
> dashboards for Finance, Marketing, and Merchandising — fully orchestrated,
> tested, documented, and runnable on a laptop with one command.

---

## Table of contents

1. [The business problem](#1-the-business-problem)
2. [The solution at a glance](#2-the-solution-at-a-glance)
3. [Architecture](#3-architecture)
4. [Tech stack and why](#4-tech-stack-and-why)
5. [Data model](#5-data-model)
6. [Pipeline orchestration](#6-pipeline-orchestration)
7. [Data quality strategy](#7-data-quality-strategy)
8. [CI/CD](#8-cicd)
9. [Results & business impact](#9-results--business-impact)
10. [Quickstart](#10-quickstart)
11. [Repository layout](#11-repository-layout)
12. [Cloud swap path](#12-cloud-swap-path-postgres--snowflake-airflow--mwaa)
13. [Roadmap](#13-roadmap)
14. [About the author](#14-about-the-author)

---

## 1. The business problem

Imagine a mid-size online retailer (think mini-Shopify merchant doing $20–50M
in GMV per year). The company runs on a Postgres OLTP system that captures
every order, customer, product, payment, shipment, and web session. The data
is *there* — but stakeholders can't get answers out of it:

- **Finance** opens monthly books on a spreadsheet manually stitched from CSV
  exports, three days after month-end, with margin calculations that don't
  reconcile to the GL.
- **Marketing** can't tell which acquisition channels actually pay back,
  because retention is in one system, attribution in another, and revenue in
  a third.
- **Merchandising** doesn't know which SKUs are dead inventory until the
  next physical count.
- **Ops** discovers fulfilment SLA breaches only when customers complain.

Every question above is technically *answerable* from the OLTP database, but
each requires a non-trivial join, a window function, and a definition of
"completed order" that needs to be the same across every team — and that
consistency is exactly what's missing.

### What the business actually needs

| Question | Owner | Required cadence |
|---|---|---|
| What was yesterday's revenue / AOV / margin, by channel? | Finance | Daily, by 09:00 |
| What's our 7-day moving average gross margin? | Finance | Daily |
| Which acquisition channels drive customers with the highest LTV? | Marketing | Weekly |
| How does month-N retention look for the customers we acquired in month-0? | Marketing | Monthly |
| Which customers are in the "Cannot Lose Them" RFM bucket? | Marketing | Weekly |
| Where does the funnel leak — product view → cart → checkout → paid? | Marketing | Daily |
| Which SKUs haven't sold in 180 days? | Merch | Weekly |
| What's our payment capture rate, by method? | Finance / Ops | Daily |

Every one of these has to be answered from a **single source of truth** so
two teams looking at "revenue" never see two different numbers.

---

## 2. The solution at a glance

A layered ELT platform that lands raw OLTP data, transforms it through a
disciplined Kimball model, validates every layer, orchestrates the workflow,
and exposes BI-ready marts to dashboard tools.

**One command** (`make up && make seed && make dbt-build`) brings up:

- A Postgres analytical warehouse (mimics Snowflake/BigQuery in schema design)
- An Airflow scheduler running a daily ELT DAG
- A dbt project transforming raw → staging → intermediate → marts
- A Metabase instance for self-serve dashboards
- A GitHub Actions CI pipeline that runs the whole thing on every PR

The platform is **deliberately architected for the cloud swap** — switching
from local Postgres + Airflow to Snowflake + MWAA (Managed Airflow on AWS) is
a configuration change in `.env`, not a rewrite.

---

## 3. Architecture

```
                       ┌────────────────────────────────────────────────────┐
                       │                     Airflow                         │
                       │           daily_elt DAG  (07:00 UTC)                │
                       │                                                     │
                       │  wait_for_warehouse → ingest_raw → dbt_deps →       │
                       │  dbt_seed → dbt_run_staging → dbt_snapshot →        │
                       │  dbt_run_intermediate → dbt_run_marts → dbt_test →  │
                       │  dbt_docs_generate                                  │
                       └──────────┬──────────────────────────┬───────────────┘
                                  │                          │
                  ┌───────────────▼──────────┐    ┌──────────▼───────────────┐
                  │  Ingestion (Python)      │    │  dbt build                │
                  │                          │    │                           │
                  │  Faker → deterministic   │───▶│  staging  (views)         │
                  │  source generator        │    │     ↓                     │
                  │  ↓                       │    │  intermediate (ephemeral) │
                  │  Bulk-load to raw.*      │    │     ↓                     │
                  │  via execute_values()    │    │  marts.core / finance /   │
                  └──────────┬───────────────┘    │  marketing (tables)       │
                             │                    └──────────┬───────────────┘
                             │                               │
                             ▼                               ▼
                  ┌──────────────────────────────────────────────────┐
                  │             Postgres warehouse                    │
                  │                                                   │
                  │   raw.*            ← landing zone (OLTP mirror)   │
                  │   staging.*        ← cast + rename                │
                  │   intermediate.*   ← business logic CTEs          │
                  │   mart_core.*      ← conformed dims + base facts  │
                  │   mart_finance.*   ← revenue, margin, payments    │
                  │   mart_marketing.* ← cohorts, RFM, funnel         │
                  │   snapshots.*      ← SCD2 history                 │
                  └──────────────┬───────────────────────────────────┘
                                 │
                            (read-only: bi_reader role)
                                 │
                          ┌──────▼───────┐
                          │   Metabase   │
                          │  dashboards  │
                          └──────────────┘
```

### Layered modeling rationale

| Layer | Materialization | Purpose | Why this materialization |
|---|---|---|---|
| **raw** | external (loader) | Source-of-truth landing | Append-friendly, never transformed |
| **staging** | view | 1:1 with raw, cast & rename | Cheap to recompute; downstream depends on contract not data |
| **intermediate** | ephemeral | Joined CTEs, business logic blocks | Never queried directly by BI — saves warehouse storage |
| **marts** | table | Conformed dims, dashboard-ready facts | Fast read, stable contract for BI tools |
| **snapshots** | table (SCD2) | Track history of dimensions | Required for point-in-time correctness |

Why this matters: when Marketing asks "show me last March's customer
segments using the data we *had* in March," the snapshot layer can answer
that without time-travel features in the warehouse.

---

## 4. Tech stack and why

| Layer | Tool | Why this and not the alternative |
|---|---|---|
| Warehouse | **PostgreSQL 15** | Free, ubiquitous, dbt-friendly. Same SQL surface area as Snowflake/Redshift for the patterns used here. |
| Transformation | **dbt-core 1.7** | Declarative SQL DAG, lineage, tests, docs in one tool. Industry standard for analytics engineering. |
| Orchestration | **Apache Airflow 2.9** | De-facto standard. Maps cleanly onto MWAA / Cloud Composer for prod. |
| Ingestion | **Python 3.11** + `psycopg2`, `Faker` | Lightweight, deterministic; production-equivalent boundary is "writes to `raw.*`" — swap for Airbyte/Fivetran without touching dbt. |
| Data quality | **dbt tests** + `dbt-expectations` | Generic + range + value-set assertions inline with the model contract. Singular SQL tests for cross-model invariants. |
| BI | **Metabase** | Open source, fastest path to self-serve charts. |
| Containerization | **Docker Compose** | One-command bring-up; identical stack on any laptop. |
| CI | **GitHub Actions** | Free for public repos, runs the full dbt build on every PR. |
| Lint / format | **`sqlfluff`, `ruff`, `pre-commit`** | Catches drift early; runs locally and in CI. |
| Secrets | `.env` (local) → Secrets Manager (prod) | Twelve-factor; same env-var names throughout. |

---

## 5. Data model

### Sources (mirror of the OLTP system)

`raw.customers`, `raw.categories`, `raw.products`, `raw.orders`,
`raw.order_items`, `raw.payments`, `raw.shipments`, `raw.web_sessions`,
`raw.web_events`.

The synthetic generator produces a **referentially consistent** dataset of
~2k customers, 300 products, 15k orders, 40k web sessions, and ~80k events,
with realistic distributions:

- **Long-tail product popularity** (Zipfian) — a few SKUs dominate
- **Repeat-customer skew** (gaussian-ish around 3, with heavy repeaters)
- **Funnel drop-off** — 60% PDP rate, 42% ATC of PDPs, 40% checkout of ATCs, 30% purchase of checkouts
- **Realistic margin distributions** — 30–70% markup
- **Order status mix** — 78% delivered, 10% shipped, 5% paid, 5% cancelled, 2% refunded

### Conformed dimensions and facts

```
                    ┌──────────────────────┐
                    │   mart_core          │
                    │   ──────────         │
                    │   dim_dates          │ (day grain, 2022-01-01 → 2026-12-31)
                    │   dim_customers      │ (lifetime metrics + segment)
                    │   dim_products       │ (category rollup + velocity)
                    │   fct_orders         │ (1 row per order)
                    │   fct_order_items    │ (1 row per order × product)
                    └──────────────────────┘
                                │
                ┌───────────────┼────────────────────┐
                │                                    │
       ┌────────▼─────────────┐         ┌────────────▼──────────────┐
       │   mart_finance       │         │   mart_marketing          │
       │   ────────────       │         │   ────────────────        │
       │   fct_revenue_daily  │         │   fct_customer_cohorts    │
       │   fct_margin_by_     │         │   dim_customers_rfm       │
       │     category         │         │   fct_funnel_daily        │
       │   fct_payments_      │         │   fct_channel_attribution │
       │     summary          │         └───────────────────────────┘
       └──────────────────────┘
```

Every model is documented in `_models.yml` files with descriptions and tests
at both the model and column level. Run `dbt docs generate && dbt docs serve`
to browse the full lineage graph.

### Slowly-Changing Dimensions (SCD2)

Two snapshots tracked in the `snapshots` schema:

- `snap_products` — timestamp strategy on `updated_at` (price/cost changes)
- `snap_customers` — check strategy on profile columns (PII updates)

This means you can answer "what was the price of SKU-00123 on 2024-08-15?"
even if the price changed afterwards.

---

## 6. Pipeline orchestration

The `daily_elt` DAG runs at **07:00 UTC** every day:

```
start
  └── wait_for_warehouse        # pg_isready loop
       └── ingest_raw           # synthetic generator (in prod: Airbyte/Fivetran)
            └── dbt_deps        # install dbt packages
                 └── dbt_seed   # load currency_rates etc.
                      └── dbt_run_staging
                           └── dbt_snapshot     # SCD2 capture
                                └── dbt_run_intermediate
                                     └── dbt_run_marts
                                          └── dbt_test     # GATE
                                               └── dbt_docs_generate
                                                    └── end
```

- **Retries:** 2 with 5-min backoff on every task
- **Idempotency:** every task is safe to rerun manually
- **Failure handling:** `dbt_test` failure aborts the DAG before docs publish
- **SLA:** completion by 08:30 UTC (90 min after start)

---

## 7. Data quality strategy

Quality is enforced at **three** levels — every failure aborts the DAG before
bad data hits a dashboard.

### Level 1: Source contracts (`models/staging/_sources.yml`)

- `unique` + `not_null` on every primary key
- `relationships` for foreign keys (e.g. `orders.customer_id` → `customers`)
- `accepted_values` for enums (`order_status`, `event_name`, etc.)
- `dbt_expectations` ranges (e.g. `grand_total >= 0`)
- **Freshness checks** on `_ingested_at` (warn at 24h, error at 48h)

### Level 2: Model contracts (each layer's `_models.yml`)

Same generic tests applied per model, plus:

- `dbt_expectations.expect_column_values_to_be_between` for bounded fields
  (e.g. `margin_pct` ∈ [-1, 1], `r_score` ∈ [1, 5])
- `accepted_values` for derived enums (e.g. `customer_segment`,
  `product_velocity`)

### Level 3: Singular tests (`dbt/tests/`)

Cross-model business invariants that can't be expressed as a generic test:

| Test | Invariant |
|---|---|
| `assert_order_totals_match_items.sql` | `order.subtotal == sum(items.line_revenue)` within $0.02 |
| `assert_no_future_orders.sql` | No `order_ts > now()` (catches clock-skew bugs) |
| `assert_funnel_monotonic.sql` | A session with `purchase=true` must also have `checkout=true`, `atc=true`, `pdp=true` |

**Total: ~50+ tests**, all running on every CI build and every DAG run.

---

## 8. CI/CD

`.github/workflows/ci.yml` runs on every push to `main` and every PR:

1. Spin up an **ephemeral Postgres** as a GitHub Actions service
2. Install Python deps (`ingestion` + `airflow` requirements)
3. **Lint** — `ruff` on Python, `sqlfluff` on dbt models
4. **Bootstrap** — apply `sql/init/*.sql` to the ephemeral warehouse
5. **Seed** — run the synthetic loader with CI-sized data (200 customers / 800 orders)
6. **Test** — `pytest` for the Python generator (referential integrity, determinism)
7. **`dbt build`** — compile + run + test the entire DAG
8. **Upload artifacts** — `manifest.json`, `run_results.json`, `catalog.json`

If any step fails, the PR is blocked. The artifacts make it possible to host
dbt docs from a CI run on GitHub Pages.

---

## 9. Results & business impact

When deployed against the synthetic dataset (~15k orders, 40k sessions, 2.5
years of history), the platform produces:

### Operational results

| Metric | Value |
|---|---|
| Cold-start full pipeline (image build + seed + dbt build) | **~10 min** |
| Warm DAG run (daily incremental in prod) | **~2 min** |
| Models built | **22** (9 staging, 3 intermediate, 5 core, 3 finance, 4 marketing) |
| Tests executed per run | **50+** |
| Snapshots maintained | **2** (products, customers) |
| Test pass rate (clean data) | **100%** |
| CI run end-to-end | **~5 min** |

### Business questions answered out of the box

The platform answers every question listed in §1 directly from a mart, with
no further SQL gymnastics:

```sql
-- Yesterday's revenue, AOV, margin — by channel
SELECT * FROM mart_finance.fct_revenue_daily
WHERE order_date = current_date - 1;

-- Top "Cannot Lose Them" customers (high value, slipping away)
SELECT * FROM mart_marketing.dim_customers_rfm
WHERE rfm_segment = 'Cannot Lose Them'
ORDER BY monetary DESC LIMIT 50;

-- 90-day cohort retention heatmap
SELECT cohort_month, months_since_first_order, active_customers
FROM mart_marketing.fct_customer_cohorts;

-- Dead inventory — SKUs that haven't sold in 180+ days
SELECT sku, product_name, last_sold_at
FROM mart_core.dim_products
WHERE product_velocity = 'dead_inventory';
```

### How this would help in a real org

| Before this platform | After this platform |
|---|---|
| Finance closes books 3 days after month-end via manual CSV stitching | Daily revenue + margin available by 08:30 the next morning |
| Marketing argues over which "revenue" number is right | One mart, one number — `mart_finance.fct_revenue_daily` |
| Cohort analysis requested → analyst writes a 200-line query → 2 days later | `SELECT * FROM mart_marketing.fct_customer_cohorts` → instant |
| Schema drift breaks dashboards silently | dbt tests fail the pipeline; bad data never lands |
| New analyst takes a week to learn the data model | `dbt docs serve` — full ERD + lineage in a browser |
| BI dashboards talk directly to the OLTP DB and crush production | Read-only `bi_reader` role on marts; OLTP unaffected |

---

## 10. Quickstart

**Requirements:** Docker Desktop, ~6 GB free RAM, ~3 GB disk.

```bash
git clone https://github.com/Akshay-Ravirala/ecommerce-analytics-platform.git
cd ecommerce-analytics-platform

cp .env.example .env       # defaults work for local

make up                    # ~5–8 min first time (image pulls)
make seed                  # ~30s — generate + load synthetic source data
make dbt-build             # ~60s — staging → intermediate → marts + tests

# UIs
#   Airflow:  http://localhost:8080   (admin / admin)
#   Metabase: http://localhost:3000
#   psql:     make psql
```

Or trigger the full orchestrated pipeline through Airflow:

```bash
make trigger-dag
```

Browse the data model:

```bash
make dbt-docs
# open http://localhost:8081
```

Tear down completely:

```bash
make clean                 # removes volumes too
```

---

## 11. Repository layout

```
ecommerce-analytics-platform/
├── README.md                     ← you are here
├── docker-compose.yml            ← Postgres + Airflow + Metabase + dbt + ingest
├── Makefile                      ← one-line operator commands
├── .env.example                  ← all credentials / config
├── .github/workflows/ci.yml      ← CI: lint, pytest, dbt build, artifact upload
├── .pre-commit-config.yaml       ← sqlfluff + ruff hooks
├── .sqlfluff                     ← SQL style config
├── pyproject.toml                ← ruff + pytest config
├── docs/
│   ├── architecture.md           ← ADRs, deeper diagrams, swap matrix
│   ├── runbook.md                ← on-call playbook, common ops
│   └── dashboards.md             ← BI cookbook with example queries
├── sql/init/                     ← Postgres bootstrap (schemas, roles, raw tables)
├── ingestion/
│   ├── Dockerfile
│   ├── generate_data.py          ← Faker-based synthetic generator
│   ├── load_to_postgres.py       ← idempotent bulk loader → raw.*
│   └── requirements.txt
├── airflow/
│   ├── Dockerfile
│   ├── dags/daily_elt.py         ← end-to-end ELT DAG
│   └── requirements.txt
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml              ← postgres (dev/ci) + snowflake (prod) targets
│   ├── packages.yml              ← dbt_utils, dbt_expectations, codegen, dbt_date
│   ├── macros/                   ← reusable SQL helpers
│   ├── models/
│   │   ├── staging/              ← stg_*  (1:1 with raw)
│   │   ├── intermediate/         ← int_*  (joined CTEs)
│   │   └── marts/
│   │       ├── core/             ← dim_customers, dim_products, fct_orders, ...
│   │       ├── finance/          ← fct_revenue_daily, fct_margin_by_category, ...
│   │       └── marketing/        ← fct_customer_cohorts, dim_customers_rfm, ...
│   ├── snapshots/                ← SCD2 for products + customers
│   ├── seeds/                    ← currency_rates.csv
│   ├── tests/                    ← singular cross-model invariant tests
│   └── analyses/                 ← ad-hoc queries (compiled, not built)
└── tests/
    └── test_generate_data.py     ← pytest for the generator
```

---

## 12. Cloud swap path (Postgres → Snowflake, Airflow → MWAA)

This project was designed so the production swap-out is a **configuration
change, not a rewrite**. The seams are documented:

| Component | Local default | Production swap | What changes |
|---|---|---|---|
| Warehouse | Postgres 15 | Snowflake / BigQuery / Redshift | `DBT_PROFILE_TARGET=prod` + set Snowflake env vars (already wired in `profiles.yml`) |
| Orchestrator | Airflow LocalExecutor | MWAA / Cloud Composer / Astronomer | Same DAG file deployed via CI |
| Ingestion | Python loader | Airbyte / Fivetran / Meltano | Replace the `ingest` container; downstream dbt is unchanged |
| BI | Metabase | Looker / Tableau / Superset | New tool points at the same marts |
| Secrets | `.env` | AWS Secrets Manager / GCP Secret Manager | Same env-var names |
| CI | GitHub Actions | Same | Unchanged |

The dbt `profiles.yml` already defines a `prod` target pointing at Snowflake;
flipping is a one-liner:

```bash
DBT_PROFILE_TARGET=prod dbt build
```

---

## 13. Roadmap

Things I'd add next in priority order:

- [ ] **Incremental models** for `fct_orders` and `fct_order_items` (use `is_incremental()` macro) — currently full-refresh tables
- [ ] **Cosmos** (Astronomer's dbt-Airflow lib) for task-per-model parallelism
- [ ] **Great Expectations** suite alongside dbt tests for cross-table contracts
- [ ] **DataHub / OpenLineage** integration for column-level lineage outside dbt
- [ ] **Soda Core** for monitoring + alerting on data quality SLOs
- [ ] **Streamlit** companion app demonstrating the marts as a hosted app
- [ ] **Terraform** module to provision the production equivalent on AWS

---

## 14. About the author

Built by **Akshay Ravirala** as a portfolio piece demonstrating end-to-end
data engineering — from infrastructure-as-code through ingestion,
orchestration, modeling, testing, documentation, and CI/CD.

- GitHub: [@Akshay-Ravirala](https://github.com/Akshay-Ravirala)
- Email: raviralaakshaykumar@gmail.com

---

## License

[MIT](LICENSE) — free to use, fork, and adapt.
