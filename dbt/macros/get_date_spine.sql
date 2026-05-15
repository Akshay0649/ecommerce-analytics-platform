{# Thin wrapper around dbt_utils.date_spine for our standard date dimension range. #}
{% macro get_date_spine(start_date='2022-01-01', end_date='2026-01-01') %}
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ start_date ~ "' as date)",
        end_date="cast('" ~ end_date ~ "' as date)"
    ) }}
{% endmacro %}
