{# Order header enriched with item-level rollups, payment, and shipment. #}

with orders as (
    select * from {{ ref('stg_orders') }}
),

items as (
    select
        order_id,
        sum(quantity)        as items_quantity,
        count(*)             as items_count,
        sum(line_revenue)    as items_revenue,
        sum(line_cost)       as items_cost,
        sum(line_margin)     as items_margin
    from {{ ref('stg_order_items') }}
    group by 1
),

pay as (
    select
        order_id,
        max(case when is_captured then paid_at end)              as captured_at,
        bool_or(is_captured)                                     as has_capture,
        bool_or(is_failed)                                       as has_failed_attempt,
        bool_or(is_refunded)                                     as has_refund,
        max(payment_method) filter (where is_captured)           as primary_payment_method
    from {{ ref('stg_payments') }}
    group by 1
),

ship as (
    select
        order_id,
        min(shipped_at)                                          as shipped_at,
        min(delivered_at)                                        as delivered_at,
        avg(transit_days)                                        as transit_days
    from {{ ref('stg_shipments') }}
    group by 1
)

select
    o.order_id,
    o.customer_id,
    o.order_ts,
    o.order_date,
    o.order_status,
    o.order_channel,
    o.currency,

    o.subtotal_amount,
    o.shipping_amount,
    o.tax_amount,
    o.discount_amount,
    o.gross_amount,

    i.items_quantity,
    i.items_count,
    i.items_revenue,
    i.items_cost,
    i.items_margin,

    pay.captured_at,
    pay.has_capture,
    pay.has_failed_attempt,
    pay.has_refund,
    pay.primary_payment_method,

    ship.shipped_at,
    ship.delivered_at,
    ship.transit_days,

    o.is_completed,
    o.is_cancelled,
    o.is_refunded
from orders o
left join items   i   on o.order_id = i.order_id
left join pay         on o.order_id = pay.order_id
left join ship        on o.order_id = ship.order_id
