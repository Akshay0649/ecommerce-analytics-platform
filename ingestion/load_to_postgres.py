"""Idempotent loader: generate synthetic data and write to raw.* in Postgres.

Strategy:
  1. Ensure raw schema + tables exist (defensive; init SQL also creates them).
  2. TRUNCATE then bulk INSERT via execute_values for speed.
     (Production would use MERGE / CDC / chunked upserts; this is a clean rebuild.)
  3. Single transaction per table — failure rolls back, partial loads avoided.
"""

from __future__ import annotations

import logging
import os
import sys
import time
from collections.abc import Iterable

import psycopg2
import psycopg2.extras
from generate_data import generate

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("ingest")


PG_CONFIG = {
    "host": os.getenv("POSTGRES_HOST", "localhost"),
    "port": int(os.getenv("POSTGRES_PORT", "5432")),
    "dbname": os.getenv("POSTGRES_DB", "analytics"),
    "user": os.getenv("POSTGRES_USER", "analytics"),
    "password": os.getenv("POSTGRES_PASSWORD", "analytics"),
}


# Column order must match the INSERT statement.
TABLES = {
    "customers": [
        "customer_id", "email", "first_name", "last_name", "country", "city",
        "signup_ts", "marketing_channel", "is_active",
    ],
    "categories": ["category_id", "category_name", "parent_id"],
    "products": [
        "product_id", "sku", "product_name", "category_id",
        "unit_price", "unit_cost", "is_active", "created_at", "updated_at",
    ],
    "orders": [
        "order_id", "customer_id", "order_ts", "status", "channel", "currency",
        "subtotal", "shipping_amount", "tax_amount", "discount_amount", "grand_total",
    ],
    "order_items": [
        "order_item_id", "order_id", "product_id", "quantity",
        "unit_price", "unit_cost", "line_total",
    ],
    "payments": [
        "payment_id", "order_id", "payment_method", "payment_status",
        "amount", "paid_at",
    ],
    "shipments": [
        "shipment_id", "order_id", "carrier", "shipped_at", "delivered_at", "tracking_no",
    ],
    "web_sessions": [
        "session_id", "customer_id", "started_at", "ended_at", "device",
        "utm_source", "utm_medium", "utm_campaign",
    ],
    "web_events": [
        "event_id", "session_id", "event_ts", "event_name", "product_id", "order_id",
    ],
}

# Map dataclass attributes → table names (handle naming difference)
ATTR_TO_TABLE = {
    "customers": "customers",
    "categories": "categories",
    "products": "products",
    "orders": "orders",
    "order_items": "order_items",
    "payments": "payments",
    "shipments": "shipments",
    "sessions": "web_sessions",
    "events": "web_events",
}


def wait_for_postgres(retries: int = 30, delay: float = 2.0) -> None:
    last_err = None
    for i in range(retries):
        try:
            with psycopg2.connect(**PG_CONFIG) as conn:
                conn.cursor().execute("SELECT 1")
            log.info("Postgres reachable.")
            return
        except psycopg2.OperationalError as e:
            last_err = e
            log.info("Postgres not ready (attempt %d/%d): %s", i + 1, retries, e)
            time.sleep(delay)
    raise RuntimeError(f"Postgres unreachable after {retries} retries: {last_err}")


def truncate_and_load(conn, table: str, columns: list[str], rows: Iterable[dict]) -> int:
    cols_csv = ", ".join(columns)
    placeholders = "(" + ", ".join(["%s"] * len(columns)) + ")"
    insert_sql = f"INSERT INTO raw.{table} ({cols_csv}) VALUES %s"
    values = [tuple(r[c] for c in columns) for r in rows]

    with conn.cursor() as cur:
        cur.execute(f"TRUNCATE TABLE raw.{table} RESTART IDENTITY CASCADE;")
        if values:
            psycopg2.extras.execute_values(
                cur, insert_sql, values, template=placeholders, page_size=1000,
            )
    return len(values)


def main() -> int:
    wait_for_postgres()
    log.info("Generating synthetic data...")
    t0 = time.time()
    g = generate()
    log.info("Generated in %.2fs", time.time() - t0)

    payload = {
        "customers": g.customers,
        "categories": g.categories,
        "products": g.products,
        "orders": g.orders,
        "order_items": g.order_items,
        "payments": g.payments,
        "shipments": g.shipments,
        "web_sessions": g.sessions,
        "web_events": g.events,
    }

    with psycopg2.connect(**PG_CONFIG) as conn:
        conn.autocommit = False
        # Order matters: parents before children for FK-style invariants in tests.
        load_order = [
            "customers", "categories", "products", "orders", "order_items",
            "payments", "shipments", "web_sessions", "web_events",
        ]
        for table in load_order:
            cols = TABLES[table]
            n = truncate_and_load(conn, table, cols, payload[table])
            log.info("Loaded raw.%-14s rows=%d", table, n)
        conn.commit()
    log.info("All tables loaded successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
