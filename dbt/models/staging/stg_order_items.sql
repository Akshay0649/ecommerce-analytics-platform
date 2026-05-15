with src as (
    select * from {{ source('raw', 'order_items') }}
)

select
    order_item_id,
    order_id,
    product_id,
    quantity::int                                            as quantity,
    unit_price::numeric(10,2)                                as unit_price,
    unit_cost::numeric(10,2)                                 as unit_cost,
    line_total::numeric(12,2)                                as line_revenue,
    (unit_cost * quantity)::numeric(12,2)                    as line_cost,
    (line_total - (unit_cost * quantity))::numeric(12,2)     as line_margin
from src
