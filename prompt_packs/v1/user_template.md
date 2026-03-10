Write a customer support response for the following case.

Customer name: {{ customer_name }}
Issue: {{ customer_issue }}
Goal: {{ goal }}
Requested tone: {{ tone }}
Policy snippet:
{{ policy_snippet }}

{% if context %}
Additional context:
{{ context }}
{% endif %}

Return markdown with the sections Summary, Answer, and Next Steps.

