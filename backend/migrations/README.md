# Migrations

Forward-only, numbered PostgreSQL migrations. Apply in order with `psql`:

```sh
for f in migrations/*.sql; do psql "$DATABASE_URL" -f "$f"; done
```

- Each migration runs in a single transaction (`BEGIN;` … `COMMIT;`).
- Never edit a merged migration — add a new one.
- Enums append values with `ALTER TYPE … ADD VALUE` (not in a transaction block with other DDL on older Postgres; these target Postgres 14+).

| Migration | Content |
|---|---|
| 001 | Extensions, §11/§12 enums, users, sellers |
| 002 | Listings, immutable snapshots, inventory units |
| 003 | Orders (five dimensions), refund ledger, returns (IC-2a), disputes, reviews |
| 004 | Command audit, transactional outbox, indexes |
