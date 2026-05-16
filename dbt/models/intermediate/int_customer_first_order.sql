{# First completed order per customer — drives cohort assignment + new vs repeat. #}

with completed as (
    select
        customer_id,
        min(order_ts)::date  as first_order_date,
        min(order_ts)        as first_order_ts
    from {{ ref('int_orders_enriched') }}
    where is_completed
    group by 1
)

select * from completed
