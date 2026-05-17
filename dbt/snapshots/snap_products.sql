{# SCD2 over the product catalog. Tracks price/cost/active changes by updated_at. #}

{% snapshot snap_products %}
{{
    config(
        target_schema='snapshots',
        unique_key='product_id',
        strategy='timestamp',
        updated_at='updated_at',
        invalidate_hard_deletes=True,
    )
}}

select
    product_id,
    sku,
    product_name,
    category_id,
    unit_price,
    unit_cost,
    is_active,
    created_at,
    updated_at
from {{ source('raw', 'products') }}

{% endsnapshot %}
