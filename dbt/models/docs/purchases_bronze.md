# purchases_bronze

Bronze layer model. This model is a direct representation of the staging table `raw_purchases_staging` populated by Snowpipe. Minimal cleaning is applied in Glue; dbt bronze model is a pass-through for lineage and tests.

Columns:
- event_id (string): unique event id
- ts (timestamp): event timestamp in UTC
- store_id (string): store id
- customer_id (string): customer id
- product_id (string): product id
- category (string): product category
- price (float): unit price
- quantity (int): quantity
- total_amount (float): total amount
- dt (date): partition date from Glue
