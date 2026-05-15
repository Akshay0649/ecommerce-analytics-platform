with src as (
    select * from {{ source('raw', 'web_sessions') }}
)

select
    session_id,
    customer_id,
    started_at::timestamp                                    as started_at,
    ended_at::timestamp                                      as ended_at,
    started_at::date                                         as session_date,
    coalesce(lower(device), 'unknown')                       as device,
    coalesce(lower(utm_source), 'direct')                    as utm_source,
    coalesce(lower(utm_medium), 'none')                      as utm_medium,
    coalesce(lower(utm_campaign), 'none')                    as utm_campaign,
    case when ended_at is not null
         then extract(epoch from (ended_at - started_at)) / 60.0
    end                                                      as session_minutes,
    (customer_id is null)                                    as is_anonymous
from src
