{# Conformed customer dimension. Slowly-changing attributes captured separately
   in snapshots/snap_customers.sql; this is the latest-state view enriched with
   lifetime metrics. #}

with c as (
    select * from {{ ref('stg_customers') }}
),

first_order as (
    select * from {{ ref('int_customer_first_order') }}
),

lifetime as (
    select
        customer_id,
        count(*) filter (where is_completed)                   as lifetime_orders,
        sum(gross_amount) filter (where is_completed)          as lifetime_revenue,
        sum(items_margin) filter (where is_completed)          as lifetime_margin,
        max(order_ts) filter (where is_completed)              as last_order_ts,
        sum(case when is_refunded then gross_amount else 0 end) as lifetime_refunded
    from {{ ref('int_orders_enriched') }}
    group by 1
)

select
    c.customer_id,
    c.email,
    c.first_name,
    c.last_name,
    c.first_name || ' ' || c.last_name                          as full_name,
    c.country_code,
    c.city,
    c.signup_date,
    c.signup_ts,
    c.acquisition_channel,
    c.is_active,

    first_order.first_order_date,
    case when first_order.first_order_date is not null
         then date_trunc('month', first_order.first_order_date)::date
    end                                                          as cohort_month,

    coalesce(lifetime.lifetime_orders, 0)                        as lifetime_orders,
    coalesce(lifetime.lifetime_revenue, 0)::numeric(14,2)        as lifetime_revenue,
    coalesce(lifetime.lifetime_margin, 0)::numeric(14,2)         as lifetime_margin,
    coalesce(lifetime.lifetime_refunded, 0)::numeric(14,2)       as lifetime_refunded,
    lifetime.last_order_ts,

    case when lifetime.last_order_ts is null then 'never_purchased'
         when lifetime.last_order_ts >= (current_date - interval '30 days') then 'active'
         when lifetime.last_order_ts >= (current_date - interval '90 days') then 'at_risk'
         else 'churned'
    end                                                          as customer_segment
from c
left join first_order on c.customer_id = first_order.customer_id
left join lifetime    on c.customer_id = lifetime.customer_id
