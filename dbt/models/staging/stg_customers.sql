with src as (
    select * from {{ source('raw', 'customers') }}
)

select
    customer_id,
    lower(trim(email))                                       as email,
    initcap(first_name)                                      as first_name,
    initcap(last_name)                                       as last_name,
    upper(country)                                           as country_code,
    initcap(city)                                            as city,
    signup_ts::timestamp                                     as signup_ts,
    signup_ts::date                                          as signup_date,
    coalesce(marketing_channel, 'unknown')                   as acquisition_channel,
    is_active,
    _ingested_at
from src
