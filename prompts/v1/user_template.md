Write a support reply for the case below.

Customer
- Name: {{ customer_name }}
- Issue: {{ customer_issue }}
- Goal: {{ goal }}
- Requested tone: {{ tone }}

Policy
{{ policy_snippet }}

{% if context %}
Additional context
{{ context }}
{% endif %}

Return markdown with these sections:
## Summary
## Answer
## Next Steps

The reply must be specific to this case, operationally clear, and suitable for a customer support agent to send.
