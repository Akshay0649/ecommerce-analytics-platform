with src as (
    select * from {{ source('raw', 'payments') }}
)

select
    payment_id,
    order_id,
    lower(payment_method)                                    as payment_method,
    lower(payment_status)                                    as payment_status,
    amount::numeric(12,2)                                    as amount,
    paid_at::timestamp                                       as paid_at,
    (lower(payment_status) = 'captured')                     as is_captured,
    (lower(payment_status) = 'refunded')                     as is_refunded,
    (lower(payment_status) = 'failed')                       as is_failed
from src
