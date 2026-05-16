{# Daily revenue / orders / AOV / margin aggregated from completed orders.
   Grain: 1 row per (order_date, channel). #}

select
    order_date,
    order_channel,
    count(*)                                                         as orders_count,
    count(distinct customer_id)                                      as unique_customers,
    sum(case when customer_order_type = 'new' then 1 else 0 end)     as new_customer_orders,
    sum(case when customer_order_type = 'repeat' then 1 else 0 end)  as repeat_customer_orders,
    sum(items_quantity)                                              as units_sold,
    sum(gross_revenue)::numeric(14,2)                                as gross_revenue,
    sum(items_revenue)::numeric(14,2)                                as net_item_revenue,
    sum(discount_amount)::numeric(14,2)                              as discounts,
    sum(shipping_amount)::numeric(14,2)                              as shipping,
    sum(tax_amount)::numeric(14,2)                                   as tax,
    sum(gross_margin)::numeric(14,2)                                 as gross_margin,
    case when sum(gross_revenue) > 0
         then round((sum(gross_margin) / sum(gross_revenue))::numeric, 4)
         else 0 end                                                  as margin_pct,
    case when count(*) > 0
         then round((sum(gross_revenue) / count(*))::numeric, 2)
         else 0 end                                                  as average_order_value
from {{ ref('fct_orders') }}
where is_completed
group by 1, 2
