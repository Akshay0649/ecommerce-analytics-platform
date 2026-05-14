"""Daily ELT pipeline.

Flow:
    wait_for_warehouse → ingest_raw → dbt_deps → dbt_seed → dbt_run_staging
        → dbt_run_intermediate → dbt_run_marts → dbt_test → dbt_docs_generate
        → publish_freshness

The DAG runs daily at 07:00 UTC. Failure on any step pages on-call (slack hook
in real prod). Each task is idempotent so manual reruns are safe.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from airflow.providers.common.sql.sensors.sql import SqlSensor

DBT_DIR = "/opt/dbt"
INGEST_DIR = "/opt/ingestion"
DBT_TARGET = os.getenv("DBT_PROFILE_TARGET", "dev")

DEFAULT_ARGS = {
    "owner": "data-platform",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(hours=1),
    "email_on_failure": False,
}

# Common env passed to bash tasks so dbt picks up the right profile.
DBT_ENV = {
    "DBT_PROFILES_DIR": DBT_DIR,
    "DBT_PROFILE_TARGET": DBT_TARGET,
    "POSTGRES_HOST": os.getenv("POSTGRES_HOST", "postgres"),
    "POSTGRES_PORT": os.getenv("POSTGRES_PORT", "5432"),
    "POSTGRES_DB": os.getenv("POSTGRES_DB", "analytics"),
    "POSTGRES_USER": os.getenv("POSTGRES_USER", "analytics"),
    "POSTGRES_PASSWORD": os.getenv("POSTGRES_PASSWORD", "analytics"),
    "DBT_THREADS": os.getenv("DBT_THREADS", "4"),
}


with DAG(
    dag_id="daily_elt",
    description="End-to-end ELT: ingest → dbt build → tests → docs",
    default_args=DEFAULT_ARGS,
    schedule="0 7 * * *",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["elt", "dbt", "production"],
    doc_md=__doc__,
) as dag:

    start = EmptyOperator(task_id="start")

    # 1. Wait until the warehouse is queryable.
    # Using SqlSensor instead of PostgresOperator so this works regardless
    # of whether the airflow-postgres connection is pre-seeded.
    wait_for_warehouse = BashOperator(
        task_id="wait_for_warehouse",
        bash_command=(
            'until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" '
            '-U "$POSTGRES_USER" -d "$POSTGRES_DB"; do '
            '  echo "warehouse not ready, sleeping"; sleep 3; done'
        ),
        env=DBT_ENV,
    )

    # 2. Ingest synthetic source data into raw.* (in real prod: Airbyte / Fivetran).
    ingest_raw = BashOperator(
        task_id="ingest_raw",
        bash_command=f"cd {INGEST_DIR} && python load_to_postgres.py",
        env=DBT_ENV,
    )

    # 3. dbt: install packages, seed reference data.
    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=f"cd {DBT_DIR} && dbt deps --target $DBT_PROFILE_TARGET",
        env=DBT_ENV,
    )

    dbt_seed = BashOperator(
        task_id="dbt_seed",
        bash_command=f"cd {DBT_DIR} && dbt seed --target $DBT_PROFILE_TARGET",
        env=DBT_ENV,
    )

    # 4. Layered dbt run: staging → intermediate → marts.
    dbt_run_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command=(
            f"cd {DBT_DIR} && dbt run "
            "--select tag:staging --target $DBT_PROFILE_TARGET"
        ),
        env=DBT_ENV,
    )

    dbt_snapshot = BashOperator(
        task_id="dbt_snapshot",
        bash_command=f"cd {DBT_DIR} && dbt snapshot --target $DBT_PROFILE_TARGET",
        env=DBT_ENV,
    )

    dbt_run_intermediate = BashOperator(
        task_id="dbt_run_intermediate",
        bash_command=(
            f"cd {DBT_DIR} && dbt run "
            "--select tag:intermediate --target $DBT_PROFILE_TARGET"
        ),
        env=DBT_ENV,
    )

    dbt_run_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command=(
            f"cd {DBT_DIR} && dbt run "
            "--select tag:marts --target $DBT_PROFILE_TARGET"
        ),
        env=DBT_ENV,
    )

    # 5. Quality gate: tests must pass.
    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"cd {DBT_DIR} && dbt test --target $DBT_PROFILE_TARGET",
        env=DBT_ENV,
    )

    # 6. Refresh docs site / artifacts.
    dbt_docs = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=(
            f"cd {DBT_DIR} && dbt docs generate --target $DBT_PROFILE_TARGET"
        ),
        env=DBT_ENV,
    )

    end = EmptyOperator(task_id="end")

    (
        start
        >> wait_for_warehouse
        >> ingest_raw
        >> dbt_deps
        >> dbt_seed
        >> dbt_run_staging
        >> dbt_snapshot
        >> dbt_run_intermediate
        >> dbt_run_marts
        >> dbt_test
        >> dbt_docs
        >> end
    )
