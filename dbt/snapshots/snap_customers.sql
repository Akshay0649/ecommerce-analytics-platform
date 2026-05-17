{# SCD2 over customers using check strategy on profile-changing columns. #}

{% snapshot snap_customers %}
{{
    config(
        target_schema='snapshots',
        unique_key='customer_id',
        strategy='check',
        check_cols=['email', 'first_name', 'last_name', 'country',
                    'city', 'marketing_channel', 'is_active'],
        invalidate_hard_deletes=True,
    )
}}

select
    customer_id,
    email,
    first_name,
    last_name,
    country,
    city,
    signup_ts,
    marketing_channel,
    is_active
from {{ source('raw', 'customers') }}

{% endsnapshot %}
