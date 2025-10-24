# dbt Tests added

This repo includes the following tests:

- **Built-in tests** in `dbt/models/schema.yml` for `not_null`, `unique`, and `relationships`.
- **Custom data test** `test_total_amount_consistency.sql` which fails if `total_amount` != `price * quantity` within a small tolerance.

Run tests with:

```bash
cd dbt
dbt run
dbt test --select tag:test
# or run all tests
dbt test
```

Note: The relationships test references `dim_products` which is included as a model. If you adapt your product dimension implementation, update the test accordingly.
