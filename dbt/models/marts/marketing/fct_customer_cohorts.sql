{# Cohort retention: for each (signup_month, months_since_first_order),
   how many customers were retained and how much revenue did they bring? #}

with first_order as (
    select * from {{ ref('int_customer_first_order') }}
),

orders as (
    select
        o.customer_id,
        o.order_date,
        o.gross_revenue
    from {{ ref('fct_orders') }} o
    where o.is_completed
),

joined as (
    select
        date_trunc('month', f.first_order_date)::date           as cohort_month,
        f.customer_id,
        o.order_date,
        o.gross_revenue,
        (extract(year  from o.order_date) - extract(year  from f.first_order_date)) * 12
        + (extract(month from o.order_date) - extract(month from f.first_order_date))
                                                                as months_since_first_order
    from first_order f
    join orders o on f.customer_id = o.customer_id
)

select
    cohort_month,
    months_since_first_order::int                               as months_since_first_order,
    count(distinct customer_id)                                 as active_customers,
    count(*)                                                    as orders_count,
    sum(gross_revenue)::numeric(14,2)                           as cohort_revenue
from joined
group by 1, 2
order by 1, 2
