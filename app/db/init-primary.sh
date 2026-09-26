#!/usr/bin/env bash
# Runs once, when the primary initialises an empty data directory. Standbys receive
# the result (roles, schema, pg_hba.conf) through pg_basebackup.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username postgres <<SQL
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';
CREATE ROLE app WITH LOGIN PASSWORD '${APP_DB_PASSWORD}';
CREATE DATABASE appdb OWNER app;
SQL

psql -v ON_ERROR_STOP=1 --username app --dbname appdb <<'SQL'
CREATE TABLE products (
  id    serial PRIMARY KEY,
  name  text NOT NULL,
  price numeric(10, 2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE orders (
  id         serial PRIMARY KEY,
  product_id int NOT NULL REFERENCES products (id),
  quantity   int NOT NULL DEFAULT 1 CHECK (quantity > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO products (name, price) VALUES
  ('Keyboard', 49.90),
  ('Mouse', 19.50),
  ('Monitor', 189.00);
SQL

echo "host replication replicator ${VCN_CIDR} scram-sha-256" >> "$PGDATA/pg_hba.conf"
