with src as (
    select * from {{ source('raw', 'products') }}
)

select
    product_id,
    sku,
    product_name,
    category_id,
    unit_price::numeric(10,2)                                as unit_price,
    unit_cost::numeric(10,2)                                 as unit_cost,
    (unit_price - unit_cost)::numeric(10,2)                  as unit_margin,
    case when unit_price > 0
         then round(((unit_price - unit_cost) / unit_price)::numeric, 4)
         else 0 end                                          as margin_pct,
    is_active,
    created_at::timestamp                                    as created_at,
    updated_at::timestamp                                    as updated_at
from src
