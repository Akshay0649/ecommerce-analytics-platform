with src as (
    select * from {{ source('raw', 'categories') }}
)

select
    category_id,
    initcap(category_name)                                   as category_name,
    parent_id                                                as parent_category_id
from src
