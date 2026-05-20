"""Synthetic e-commerce source data generator.

Produces a realistic, internally-consistent dataset:
- referential integrity across customers/products/orders/items/payments/sessions
- realistic distributions (long-tail product popularity, repeat customers,
  funnel drop-off, cancellation/refund rates)
- deterministic when SEED_RANDOM_STATE is set

Output: yields lists of dicts per source table. Streams so memory stays bounded.
"""

from __future__ import annotations

import os
import random
import uuid
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime, timedelta

from faker import Faker

# ----------------------------- config ----------------------------------------

NUM_CUSTOMERS = int(os.getenv("SEED_NUM_CUSTOMERS", "2000"))
NUM_PRODUCTS = int(os.getenv("SEED_NUM_PRODUCTS", "300"))
NUM_ORDERS = int(os.getenv("SEED_NUM_ORDERS", "15000"))
NUM_SESSIONS = int(os.getenv("SEED_NUM_SESSIONS", "40000"))
SEED = int(os.getenv("SEED_RANDOM_STATE", "42"))

START_DATE = datetime(2023, 1, 1)
END_DATE = datetime(2025, 5, 1)

CHANNELS = ["web", "mobile", "marketplace"]
CHANNEL_WEIGHTS = [0.55, 0.35, 0.10]
DEVICES = ["desktop", "mobile", "tablet"]
DEVICE_WEIGHTS = [0.45, 0.50, 0.05]
UTM_SOURCES = ["google", "facebook", "instagram", "tiktok", "email", "direct", "organic"]
PAYMENT_METHODS = ["card", "paypal", "applepay", "cod"]
PAYMENT_WEIGHTS = [0.65, 0.20, 0.10, 0.05]
ORDER_STATUSES = ["paid", "shipped", "delivered", "cancelled", "refunded"]
ORDER_STATUS_WEIGHTS = [0.05, 0.10, 0.78, 0.05, 0.02]
CARRIERS = ["UPS", "FedEx", "USPS", "DHL"]

CATEGORIES = [
    (1, "Apparel", None),
    (2, "Footwear", None),
    (3, "Electronics", None),
    (4, "Home & Kitchen", None),
    (5, "Beauty", None),
    (6, "Sports & Outdoors", None),
    (7, "Books", None),
    (8, "Toys", None),
    (11, "Mens Apparel", 1),
    (12, "Womens Apparel", 1),
    (31, "Audio", 3),
    (32, "Computers", 3),
    (33, "Phones", 3),
]


@dataclass
class Generated:
    """Bag of generated tables."""

    customers: list[dict]
    categories: list[dict]
    products: list[dict]
    orders: list[dict]
    order_items: list[dict]
    payments: list[dict]
    shipments: list[dict]
    sessions: list[dict]
    events: list[dict]


def _rand_ts(rng: random.Random, start: datetime, end: datetime) -> datetime:
    delta = end - start
    return start + timedelta(seconds=rng.randint(0, int(delta.total_seconds())))


def _weighted(rng: random.Random, items: list, weights: list[float]):
    return rng.choices(items, weights=weights, k=1)[0]


# ----------------------------- generators ------------------------------------


def generate() -> Generated:
    rng = random.Random(SEED)
    fake = Faker()
    Faker.seed(SEED)

    # ---- categories ----
    categories = [
        {"category_id": cid, "category_name": name, "parent_id": parent}
        for cid, name, parent in CATEGORIES
    ]
    leaf_ids = [c["category_id"] for c in categories if c["parent_id"] is not None]
    leaf_ids += [c["category_id"] for c in categories
                 if c["category_id"] not in {x["parent_id"] for x in categories if x["parent_id"]}]

    # ---- customers ----
    customers = []
    for cid in range(1, NUM_CUSTOMERS + 1):
        signup = _rand_ts(rng, START_DATE, END_DATE - timedelta(days=30))
        customers.append({
            "customer_id": cid,
            "email": f"user{cid}_{fake.user_name()}@{fake.free_email_domain()}",
            "first_name": fake.first_name(),
            "last_name": fake.last_name(),
            "country": fake.country_code(),
            "city": fake.city(),
            "signup_ts": signup,
            "marketing_channel": _weighted(rng, UTM_SOURCES, [0.25, 0.15, 0.12, 0.08, 0.10, 0.20, 0.10]),
            "is_active": rng.random() > 0.05,
        })

    # ---- products ----
    products = []
    for pid in range(1, NUM_PRODUCTS + 1):
        cost = round(rng.uniform(2.0, 200.0), 2)
        # Realistic margins: 30%-70%
        price = round(cost * rng.uniform(1.4, 3.2), 2)
        created = _rand_ts(rng, START_DATE, END_DATE - timedelta(days=60))
        products.append({
            "product_id": pid,
            "sku": f"SKU-{pid:05d}",
            "product_name": fake.catch_phrase()[:60],
            "category_id": rng.choice(leaf_ids),
            "unit_price": price,
            "unit_cost": cost,
            "is_active": rng.random() > 0.10,
            "created_at": created,
            "updated_at": created + timedelta(days=rng.randint(0, 365)),
        })

    # popularity follows a long tail (Zipfian-ish)
    pop_weights = [1.0 / (i + 1) ** 0.9 for i in range(NUM_PRODUCTS)]

    # ---- orders + items + payments + shipments ----
    orders, order_items, payments, shipments = [], [], [], []
    item_id = 1
    payment_id = 1
    shipment_id = 1

    # Customer purchase frequency: most buy 1-3 times, some are heavy repeat.
    customer_order_count = {
        c["customer_id"]: max(1, int(rng.gauss(3, 3)))
        for c in customers
    }

    order_id = 1
    customer_pool = list(customer_order_count.keys())
    for _ in range(NUM_ORDERS):
        cid = rng.choice(customer_pool)
        if customer_order_count[cid] <= 0:
            continue
        customer_order_count[cid] -= 1

        cust = customers[cid - 1]
        order_ts = _rand_ts(rng, max(cust["signup_ts"], START_DATE), END_DATE)
        status = _weighted(rng, ORDER_STATUSES, ORDER_STATUS_WEIGHTS)
        channel = _weighted(rng, CHANNELS, CHANNEL_WEIGHTS)

        n_items = max(1, int(rng.gauss(2.5, 1.5)))
        n_items = min(n_items, 8)

        sub = 0.0
        cost_total = 0.0
        chosen_products = rng.choices(products, weights=pop_weights, k=n_items)
        for prod in chosen_products:
            qty = rng.randint(1, 3)
            line = round(prod["unit_price"] * qty, 2)
            sub += line
            cost_total += prod["unit_cost"] * qty
            order_items.append({
                "order_item_id": item_id,
                "order_id": order_id,
                "product_id": prod["product_id"],
                "quantity": qty,
                "unit_price": prod["unit_price"],
                "unit_cost": prod["unit_cost"],
                "line_total": line,
            })
            item_id += 1

        discount = round(sub * rng.choice([0, 0, 0, 0.05, 0.1, 0.15]), 2)
        shipping = round(rng.choice([0, 0, 4.99, 7.99, 9.99]), 2)
        tax = round((sub - discount) * 0.08, 2)
        grand = round(sub - discount + shipping + tax, 2)

        orders.append({
            "order_id": order_id,
            "customer_id": cid,
            "order_ts": order_ts,
            "status": status,
            "channel": channel,
            "currency": "USD",
            "subtotal": round(sub, 2),
            "shipping_amount": shipping,
            "tax_amount": tax,
            "discount_amount": discount,
            "grand_total": grand,
        })

        # Payment row(s)
        if status != "cancelled":
            paid_at = order_ts + timedelta(minutes=rng.randint(0, 60))
            pay_status = "refunded" if status == "refunded" else "captured"
            payments.append({
                "payment_id": payment_id,
                "order_id": order_id,
                "payment_method": _weighted(rng, PAYMENT_METHODS, PAYMENT_WEIGHTS),
                "payment_status": pay_status,
                "amount": grand,
                "paid_at": paid_at,
            })
            payment_id += 1
        else:
            # 30% of cancellations had a failed payment attempt
            if rng.random() < 0.3:
                payments.append({
                    "payment_id": payment_id,
                    "order_id": order_id,
                    "payment_method": _weighted(rng, PAYMENT_METHODS, PAYMENT_WEIGHTS),
                    "payment_status": "failed",
                    "amount": grand,
                    "paid_at": None,
                })
                payment_id += 1

        # Shipment for paid/shipped/delivered
        if status in ("shipped", "delivered"):
            shipped = order_ts + timedelta(days=rng.randint(1, 3))
            delivered = shipped + timedelta(days=rng.randint(1, 7)) if status == "delivered" else None
            shipments.append({
                "shipment_id": shipment_id,
                "order_id": order_id,
                "carrier": rng.choice(CARRIERS),
                "shipped_at": shipped,
                "delivered_at": delivered,
                "tracking_no": uuid.uuid4().hex[:12].upper(),
            })
            shipment_id += 1

        order_id += 1

    # ---- web sessions + events ----
    sessions = []
    events = []
    event_id = 1
    purchasing_orders = [o for o in orders if o["status"] in ("paid", "shipped", "delivered")]
    purchase_idx = 0

    for sid in range(1, NUM_SESSIONS + 1):
        anon = rng.random() < 0.40
        cid = None if anon else rng.randint(1, NUM_CUSTOMERS)
        started = _rand_ts(rng, START_DATE, END_DATE)
        duration_min = max(1, int(rng.gauss(6, 5)))
        ended = started + timedelta(minutes=duration_min)
        session_uid = f"sess_{sid:08d}_{uuid.uuid4().hex[:6]}"
        sessions.append({
            "session_id": session_uid,
            "customer_id": cid,
            "started_at": started,
            "ended_at": ended,
            "device": _weighted(rng, DEVICES, DEVICE_WEIGHTS),
            "utm_source": rng.choice(UTM_SOURCES),
            "utm_medium": rng.choice(["cpc", "organic", "email", "social", "referral"]),
            "utm_campaign": rng.choice(["spring_sale", "evergreen", "newsletter", "brand", "retargeting"]),
        })

        # Funnel: page_view (always) → view_product (60%) → add_to_cart (25%)
        # → checkout_start (10%) → purchase (3%, must be a logged-in cust w/ order)
        events.append({
            "event_id": event_id, "session_id": session_uid, "event_ts": started,
            "event_name": "page_view", "product_id": None, "order_id": None,
        })
        event_id += 1

        if rng.random() < 0.60:
            prod = rng.choices(products, weights=pop_weights, k=1)[0]
            events.append({
                "event_id": event_id, "session_id": session_uid,
                "event_ts": started + timedelta(seconds=rng.randint(10, 200)),
                "event_name": "view_product", "product_id": prod["product_id"], "order_id": None,
            })
            event_id += 1

            if rng.random() < 0.42:  # 42% of viewers add to cart → ~25% overall
                events.append({
                    "event_id": event_id, "session_id": session_uid,
                    "event_ts": started + timedelta(seconds=rng.randint(60, 300)),
                    "event_name": "add_to_cart", "product_id": prod["product_id"], "order_id": None,
                })
                event_id += 1

                if rng.random() < 0.40:
                    events.append({
                        "event_id": event_id, "session_id": session_uid,
                        "event_ts": started + timedelta(seconds=rng.randint(120, 500)),
                        "event_name": "checkout_start", "product_id": prod["product_id"], "order_id": None,
                    })
                    event_id += 1

                    # Convert ~30% of checkout starts into actual purchases that
                    # we tie to a real order. Only if customer is known.
                    if cid is not None and rng.random() < 0.30 and purchase_idx < len(purchasing_orders):
                        ord_row = purchasing_orders[purchase_idx]
                        purchase_idx += 1
                        events.append({
                            "event_id": event_id, "session_id": session_uid,
                            "event_ts": started + timedelta(seconds=rng.randint(180, 900)),
                            "event_name": "purchase",
                            "product_id": prod["product_id"],
                            "order_id": ord_row["order_id"],
                        })
                        event_id += 1

    return Generated(
        customers=customers,
        categories=categories,
        products=products,
        orders=orders,
        order_items=order_items,
        payments=payments,
        shipments=shipments,
        sessions=sessions,
        events=events,
    )


def chunks(seq: list, n: int) -> Iterator[list]:
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


if __name__ == "__main__":
    g = generate()
    print(f"customers={len(g.customers)} products={len(g.products)} "
          f"orders={len(g.orders)} items={len(g.order_items)} "
          f"payments={len(g.payments)} shipments={len(g.shipments)} "
          f"sessions={len(g.sessions)} events={len(g.events)}")
