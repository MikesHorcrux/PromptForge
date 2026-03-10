Draft a customer support reply using the policy provided.

Customer name: {{ customer_name }}
Issue: {{ customer_issue }}
Primary goal: {{ goal }}
Target tone: {{ tone }}

Policy source:
{{ policy_snippet }}

{% if context %}
Operational context:
{{ context }}
{% endif %}

Return markdown with exactly these sections:
## Summary
## Answer
## Next Steps

The reply must be specific, scannable, and grounded in the policy text above.

