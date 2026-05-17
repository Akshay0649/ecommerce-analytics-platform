-- Ad-hoc: top 25 products by revenue in the last 30 days. Compiled but not run.

select
    dp.sku,
    dp.product_name,
    dp.parent_category_name,
    sum(foi.quantity)        as units_sold,
    sum(foi.line_revenue)    as revenue,
    sum(foi.line_margin)     as margin
from {{ ref('fct_order_items') }} foi
join {{ ref('dim_products') }} dp on foi.product_id = dp.product_id
where foi.is_completed
  and foi.order_date >= current_date - interval '30 days'
group by 1, 2, 3
order by revenue desc
limit 25
