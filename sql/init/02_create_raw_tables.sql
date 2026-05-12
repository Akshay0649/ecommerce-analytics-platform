-- Raw landing tables. Mirror an OLTP system. Append-friendly.
-- Loader truncates + inserts on each run; production would use CDC.

CREATE TABLE IF NOT EXISTS raw.customers (
    customer_id       BIGINT PRIMARY KEY,
    email             TEXT NOT NULL,
    first_name        TEXT,
    last_name         TEXT,
    country           TEXT,
    city              TEXT,
    signup_ts         TIMESTAMP NOT NULL,
    marketing_channel TEXT,
    is_active         BOOLEAN DEFAULT TRUE,
    _ingested_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.categories (
    category_id   BIGINT PRIMARY KEY,
    category_name TEXT NOT NULL,
    parent_id     BIGINT,
    _ingested_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.products (
    product_id    BIGINT PRIMARY KEY,
    sku           TEXT UNIQUE NOT NULL,
    product_name  TEXT NOT NULL,
    category_id   BIGINT NOT NULL,
    unit_price    NUMERIC(10,2) NOT NULL,
    unit_cost     NUMERIC(10,2) NOT NULL,
    is_active     BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMP NOT NULL,
    updated_at    TIMESTAMP NOT NULL,
    _ingested_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.orders (
    order_id        BIGINT PRIMARY KEY,
    customer_id     BIGINT NOT NULL,
    order_ts        TIMESTAMP NOT NULL,
    status          TEXT NOT NULL,    -- pending|paid|shipped|delivered|cancelled|refunded
    channel         TEXT,             -- web|mobile|marketplace
    currency        TEXT DEFAULT 'USD',
    subtotal        NUMERIC(12,2) NOT NULL,
    shipping_amount NUMERIC(12,2) NOT NULL,
    tax_amount      NUMERIC(12,2) NOT NULL,
    discount_amount NUMERIC(12,2) NOT NULL,
    grand_total     NUMERIC(12,2) NOT NULL,
    _ingested_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.order_items (
    order_item_id BIGINT PRIMARY KEY,
    order_id      BIGINT NOT NULL,
    product_id    BIGINT NOT NULL,
    quantity      INT NOT NULL,
    unit_price    NUMERIC(10,2) NOT NULL,
    unit_cost     NUMERIC(10,2) NOT NULL,
    line_total    NUMERIC(12,2) NOT NULL,
    _ingested_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.payments (
    payment_id     BIGINT PRIMARY KEY,
    order_id       BIGINT NOT NULL,
    payment_method TEXT NOT NULL,    -- card|paypal|applepay|cod
    payment_status TEXT NOT NULL,    -- captured|failed|refunded
    amount         NUMERIC(12,2) NOT NULL,
    paid_at        TIMESTAMP,
    _ingested_at   TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.shipments (
    shipment_id    BIGINT PRIMARY KEY,
    order_id       BIGINT NOT NULL,
    carrier        TEXT,
    shipped_at     TIMESTAMP,
    delivered_at   TIMESTAMP,
    tracking_no    TEXT,
    _ingested_at   TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.web_sessions (
    session_id     TEXT PRIMARY KEY,
    customer_id    BIGINT,           -- nullable: anonymous
    started_at     TIMESTAMP NOT NULL,
    ended_at       TIMESTAMP,
    device         TEXT,             -- desktop|mobile|tablet
    utm_source     TEXT,
    utm_medium     TEXT,
    utm_campaign   TEXT,
    _ingested_at   TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS raw.web_events (
    event_id       BIGINT PRIMARY KEY,
    session_id     TEXT NOT NULL,
    event_ts       TIMESTAMP NOT NULL,
    event_name     TEXT NOT NULL,    -- page_view|view_product|add_to_cart|checkout_start|purchase
    product_id     BIGINT,
    order_id       BIGINT,
    _ingested_at   TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_customer  ON raw.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_ts        ON raw.orders(order_ts);
CREATE INDEX IF NOT EXISTS idx_items_order      ON raw.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_items_product    ON raw.order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_events_session   ON raw.web_events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_ts        ON raw.web_events(event_ts);
