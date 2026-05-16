{# Grain: 1 row per order. The canonical revenue fact for the business. #}

with o as (
    select * from {{ ref('int_orders_enriched') }}
),

cust as (
    select * from {{ ref('int_customer_first_order') }}
)

select
    o.order_id,
    o.customer_id,
    o.order_ts,
    o.order_date,
    o.order_status,
    o.order_channel,
    o.currency,
    o.primary_payment_method,

    o.subtotal_amount,
    o.shipping_amount,
    o.tax_amount,
    o.discount_amount,
    o.gross_amount                                             as gross_revenue,

    o.items_quantity,
    o.items_count,
    o.items_revenue,
    o.items_cost,
    o.items_margin                                             as gross_margin,
    case when o.items_revenue > 0
         then round((o.items_margin / o.items_revenue)::numeric, 4)
         else 0 end                                            as margin_pct,

    case when o.order_date = cust.first_order_date
         then 'new' else 'repeat' end                          as customer_order_type,

    o.is_completed,
    o.is_cancelled,
    o.is_refunded,

    o.shipped_at,
    o.delivered_at,
    o.transit_days
from o
left join cust on o.customer_id = cust.customer_id
