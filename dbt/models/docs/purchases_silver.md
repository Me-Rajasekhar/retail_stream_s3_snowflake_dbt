# purchases_silver

Silver layer model. Conforms types, normalizes category text, and ensures required columns exist. This is the starting point for enrichment and joining dimension tables (products, stores, customers).

Transforms:
- lower(category) -> category
- date_trunc('day', ts) -> day
- filters out events with missing event_id or ts
