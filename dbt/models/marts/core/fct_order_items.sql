{# Grain: 1 row per (order, product). Used for product / category analysis. #}

select
    oi.order_item_id,
    oi.order_id,
    o.customer_id,
    o.order_date,
    o.order_status,
    o.order_channel,
    oi.product_id,
    oi.quantity,
    oi.unit_price,
    oi.unit_cost,
    oi.line_revenue,
    oi.line_cost,
    oi.line_margin,
    o.is_completed,
    o.is_refunded
from {{ ref('stg_order_items') }} oi
join {{ ref('int_orders_enriched') }} o on oi.order_id = o.order_id
