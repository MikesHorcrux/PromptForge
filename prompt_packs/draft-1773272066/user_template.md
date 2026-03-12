Use the provided input payload to answer the request.

{{ input | tojson(indent=2) if input is mapping else input }}
