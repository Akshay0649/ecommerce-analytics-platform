with src as (
    select * from {{ source('raw', 'web_events') }}
)

select
    event_id,
    session_id,
    event_ts::timestamp                                      as event_ts,
    event_ts::date                                           as event_date,
    lower(event_name)                                        as event_name,
    product_id,
    order_id
from src
