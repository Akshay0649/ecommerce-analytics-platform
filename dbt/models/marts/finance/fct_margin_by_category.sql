{# Daily margin breakdown by product parent category.
   Grain: 1 row per (date, parent_category). #}

select
    foi.order_date                                                 as order_date,
    dp.parent_category_name                                        as parent_category_name,
    sum(foi.quantity)                                              as units_sold,
    sum(foi.line_revenue)::numeric(14,2)                           as revenue,
    sum(foi.line_cost)::numeric(14,2)                              as cost,
    sum(foi.line_margin)::numeric(14,2)                            as margin,
    case when sum(foi.line_revenue) > 0
         then round((sum(foi.line_margin) / sum(foi.line_revenue))::numeric, 4)
         else 0 end                                                as margin_pct
from {{ ref('fct_order_items') }} foi
join {{ ref('dim_products') }} dp on foi.product_id = dp.product_id
where foi.is_completed
group by 1, 2
