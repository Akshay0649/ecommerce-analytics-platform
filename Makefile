.PHONY: help up down restart logs ps build seed dbt-build dbt-run dbt-test dbt-docs trigger-dag airflow-init psql clean fmt lint test pre-commit

SHELL := /bin/bash
COMPOSE := docker compose --env-file .env

help:
	@echo "make up             - bring up all services (postgres, airflow, metabase)"
	@echo "make down           - tear everything down (keeps volumes)"
	@echo "make clean          - tear everything down AND wipe volumes"
	@echo "make airflow-init   - initialize Airflow DB and admin user"
	@echo "make seed           - generate synthetic source data into raw.*"
	@echo "make dbt-build      - run staging+intermediate+marts with tests"
	@echo "make dbt-test       - just run tests"
	@echo "make dbt-docs       - generate and serve dbt docs at :8081"
	@echo "make trigger-dag    - trigger the daily_elt DAG via Airflow CLI"
	@echo "make psql           - psql shell into the warehouse"
	@echo "make fmt / lint / test / pre-commit"

up:
	cp -n .env.example .env || true
	$(COMPOSE) up -d postgres airflow-db
	$(COMPOSE) up -d airflow-init
	$(COMPOSE) up -d airflow-webserver airflow-scheduler metabase

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down -v

restart: down up

logs:
	$(COMPOSE) logs -f --tail=100

ps:
	$(COMPOSE) ps

airflow-init:
	$(COMPOSE) up airflow-init

seed:
	$(COMPOSE) --profile tools run --rm ingest python load_to_postgres.py

dbt-deps:
	$(COMPOSE) --profile tools run --rm dbt deps

dbt-build: dbt-deps
	$(COMPOSE) --profile tools run --rm dbt build

dbt-run: dbt-deps
	$(COMPOSE) --profile tools run --rm dbt run

dbt-test:
	$(COMPOSE) --profile tools run --rm dbt test

dbt-docs: dbt-deps
	$(COMPOSE) --profile tools run --rm -p 8081:8081 dbt \
	  docs generate
	$(COMPOSE) --profile tools run --rm -p 8081:8081 dbt \
	  docs serve --port 8081 --host 0.0.0.0

trigger-dag:
	$(COMPOSE) exec airflow-scheduler airflow dags trigger daily_elt

psql:
	$(COMPOSE) exec postgres psql -U $${POSTGRES_USER:-analytics} -d $${POSTGRES_DB:-analytics}

fmt:
	ruff format ingestion tests
	sqlfluff fix dbt/models --dialect postgres || true

lint:
	ruff check ingestion tests
	sqlfluff lint dbt/models --dialect postgres

test:
	pytest -q

pre-commit:
	pre-commit run --all-files
