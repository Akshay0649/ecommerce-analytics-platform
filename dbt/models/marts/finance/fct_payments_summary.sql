{# Daily payment success rates and method mix.
   Used for finance / fraud / payment-ops dashboards. #}

with p as (
    select
        coalesce(paid_at::date, current_date)                       as payment_date,
        payment_method,
        payment_status,
        amount
    from {{ ref('stg_payments') }}
)

select
    payment_date,
    payment_method,
    count(*)                                                        as attempt_count,
    sum(case when payment_status = 'captured' then 1 else 0 end)    as captured_count,
    sum(case when payment_status = 'failed'   then 1 else 0 end)    as failed_count,
    sum(case when payment_status = 'refunded' then 1 else 0 end)    as refunded_count,
    sum(case when payment_status = 'captured' then amount else 0 end)::numeric(14,2) as captured_amount,
    sum(case when payment_status = 'refunded' then amount else 0 end)::numeric(14,2) as refunded_amount,
    case when count(*) > 0
         then round((sum(case when payment_status = 'captured' then 1 else 0 end)::numeric
                     / count(*)), 4)
         else 0 end                                                 as capture_rate
from p
group by 1, 2
