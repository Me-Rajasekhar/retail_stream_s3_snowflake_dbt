# dbt notes

After configuring `~/.dbt/profiles.yml` (use `dbt/profiles.yml.example`), run:

```bash
cd dbt
dbt deps
# generate docs
dbt docs generate
# serve docs to view lineage and documentation
dbt docs serve
# run models
dbt run
# run tests
dbt test
```
