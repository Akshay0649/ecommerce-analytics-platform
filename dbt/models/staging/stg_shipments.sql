with src as (
    select * from {{ source('raw', 'shipments') }}
)

select
    shipment_id,
    order_id,
    carrier,
    shipped_at::timestamp                                    as shipped_at,
    delivered_at::timestamp                                  as delivered_at,
    tracking_no,
    case when delivered_at is not null and shipped_at is not null
         then extract(epoch from (delivered_at - shipped_at)) / 86400.0
    end                                                      as transit_days
from src
