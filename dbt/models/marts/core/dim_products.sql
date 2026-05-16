{# Product dimension with category rollup and lifetime sales stats. #}

with p as (
    select * from {{ ref('stg_products') }}
),

cat as (
    select * from {{ ref('stg_categories') }}
),

cat_self as (
    select
        c.category_id,
        c.category_name,
        c.parent_category_id,
        coalesce(parent.category_name, c.category_name)          as parent_category_name
    from cat c
    left join cat parent on c.parent_category_id = parent.category_id
),

sales as (
    select
        oi.product_id,
        sum(oi.quantity)                                          as units_sold_lifetime,
        sum(oi.line_revenue)::numeric(14,2)                       as revenue_lifetime,
        sum(oi.line_margin)::numeric(14,2)                        as margin_lifetime,
        max(o.order_ts)                                           as last_sold_at
    from {{ ref('stg_order_items') }} oi
    join {{ ref('int_orders_enriched') }} o on oi.order_id = o.order_id
    where o.is_completed
    group by 1
)

select
    p.product_id,
    p.sku,
    p.product_name,
    p.category_id,
    cs.category_name,
    cs.parent_category_name,
    p.unit_price,
    p.unit_cost,
    p.unit_margin,
    p.margin_pct,
    p.is_active,
    p.created_at,
    p.updated_at,
    coalesce(sales.units_sold_lifetime, 0)                       as units_sold_lifetime,
    coalesce(sales.revenue_lifetime, 0)::numeric(14,2)           as revenue_lifetime,
    coalesce(sales.margin_lifetime, 0)::numeric(14,2)            as margin_lifetime,
    sales.last_sold_at,
    case when sales.last_sold_at is null then 'never_sold'
         when sales.last_sold_at >= (current_date - interval '30 days') then 'fast_mover'
         when sales.last_sold_at >= (current_date - interval '180 days') then 'slow_mover'
         else 'dead_inventory' end                               as product_velocity
from p
left join cat_self cs on p.category_id = cs.category_id
left join sales       on p.product_id  = sales.product_id
