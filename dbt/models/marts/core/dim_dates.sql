{{ config(materialized='table') }}

with spine as (
    {{ get_date_spine(start_date='2022-01-01', end_date='2026-12-31') }}
)

select
    date_day::date                                              as date_day,
    extract(year     from date_day)::int                        as year_number,
    extract(quarter  from date_day)::int                        as quarter_number,
    extract(month    from date_day)::int                        as month_number,
    to_char(date_day, 'YYYY-MM')                                as year_month,
    to_char(date_day, 'Mon')                                    as month_short_name,
    extract(week     from date_day)::int                        as iso_week,
    extract(day      from date_day)::int                        as day_of_month,
    extract(dow      from date_day)::int                        as day_of_week,
    to_char(date_day, 'Day')                                    as day_name,
    case when extract(dow from date_day) in (0, 6)
         then true else false end                               as is_weekend,
    date_trunc('month',   date_day)::date                       as month_start_date,
    date_trunc('quarter', date_day)::date                       as quarter_start_date,
    date_trunc('year',    date_day)::date                       as year_start_date
from spine
