Draft the final customer-facing support response for this case.

Customer details
- Name: {{ customer_name }}
- Issue: {{ customer_issue }}
- Goal: {{ goal }}
- Desired tone: {{ tone }}

Authoritative policy text
{{ policy_snippet }}

{% if context %}
Case context
{{ context }}
{% endif %}

Requirements
- Use markdown
- Use exactly these headings:
  - Summary
  - Answer
  - Next Steps
- Stay under 190 words
- Make the operational next action explicit
- Do not promise an outcome that still requires review or verification
