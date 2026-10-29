{#- Generic test: the combination of columns is unique (same idea as dbt_utils.unique_combination_of_columns, without the package) -#}
{% test unique_combination(model, columns) %}
select {{ columns | join(', ') }}, count(*) as n_rows
from {{ model }}
group by {{ columns | join(', ') }}
having count(*) > 1
{% endtest %}
