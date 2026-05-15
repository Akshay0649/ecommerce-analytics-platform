with src as (
    select * from {{ source('raw', 'orders') }}
)

select
    order_id,
    customer_id,
    order_ts::timestamp                                      as order_ts,
    order_ts::date                                           as order_date,
    lower(status)                                            as order_status,
    coalesce(lower(channel), 'unknown')                      as order_channel,
    coalesce(currency, 'USD')                                as currency,
    subtotal::numeric(12,2)                                  as subtotal_amount,
    shipping_amount::numeric(12,2)                           as shipping_amount,
    tax_amount::numeric(12,2)                                as tax_amount,
    discount_amount::numeric(12,2)                           as discount_amount,
    grand_total::numeric(12,2)                               as gross_amount,

    -- Booleans for downstream filters
    (lower(status) in ('paid','shipped','delivered'))        as is_completed,
    (lower(status) = 'cancelled')                            as is_cancelled,
    (lower(status) = 'refunded')                             as is_refunded
from src
