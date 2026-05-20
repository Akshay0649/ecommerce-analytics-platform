"""Unit tests for the synthetic data generator.

These run in CI without Postgres — they only validate the pure-Python
generator's invariants.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# Make the ingestion module importable
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ingestion"))

# Use small sizes so the test runs fast. Force-overwrite (not setdefault)
# so CI-level env vars meant for the warehouse build don't leak in here.
os.environ["SEED_NUM_CUSTOMERS"] = "100"
os.environ["SEED_NUM_PRODUCTS"] = "30"
os.environ["SEED_NUM_ORDERS"] = "300"
os.environ["SEED_NUM_SESSIONS"] = "500"
os.environ["SEED_RANDOM_STATE"] = "1"

# We import after env vars are set so the generator picks up the test-sized
# values when its module-level constants are evaluated.
import importlib

import generate_data

importlib.reload(generate_data)


def test_generator_produces_all_tables():
    g = generate_data.generate()
    assert len(g.customers) == 100
    assert len(g.products) == 30
    assert len(g.categories) > 0
    assert len(g.orders) > 0
    assert len(g.order_items) >= len(g.orders)
    assert len(g.sessions) == 500


def test_referential_integrity():
    g = generate_data.generate()

    customer_ids = {c["customer_id"] for c in g.customers}
    product_ids = {p["product_id"] for p in g.products}
    order_ids = {o["order_id"] for o in g.orders}
    session_ids = {s["session_id"] for s in g.sessions}

    assert all(o["customer_id"] in customer_ids for o in g.orders)
    assert all(i["order_id"] in order_ids for i in g.order_items)
    assert all(i["product_id"] in product_ids for i in g.order_items)
    assert all(p["order_id"] in order_ids for p in g.payments)
    assert all(s["order_id"] in order_ids for s in g.shipments)
    assert all(e["session_id"] in session_ids for e in g.events)


def test_order_totals_are_consistent():
    g = generate_data.generate()
    items_by_order: dict[int, float] = {}
    for it in g.order_items:
        items_by_order[it["order_id"]] = items_by_order.get(it["order_id"], 0) + float(it["line_total"])

    for o in g.orders:
        # subtotal should equal items sum (within rounding)
        assert abs(float(o["subtotal"]) - items_by_order[o["order_id"]]) < 0.05


def test_funnel_is_monotonic():
    """If a session contains 'purchase' it must also contain 'checkout_start'."""
    g = generate_data.generate()
    by_session: dict[str, set[str]] = {}
    for e in g.events:
        by_session.setdefault(e["session_id"], set()).add(e["event_name"])

    for sid, names in by_session.items():
        if "purchase" in names:
            assert "checkout_start" in names, f"session {sid} purchased without checkout"
        if "checkout_start" in names:
            assert "add_to_cart" in names, f"session {sid} checked out without ATC"
        if "add_to_cart" in names:
            assert "view_product" in names, f"session {sid} ATC without product view"


def test_determinism():
    g1 = generate_data.generate()
    g2 = generate_data.generate()
    # Same seed → same number of rows everywhere
    assert len(g1.orders) == len(g2.orders)
    assert len(g1.order_items) == len(g2.order_items)
    assert len(g1.events) == len(g2.events)
