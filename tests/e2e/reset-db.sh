#!/bin/bash
# Καθαρή βάση mg_e2e με όλες τις migrations και εικονικά δεδομένα
set -e
E=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$E/../.." && pwd)
P="psql -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "drop database if exists mg_e2e with (force)" -c "create database mg_e2e" >/dev/null
$P -d mg_e2e -f "$ROOT/tests/00_supabase_stub.sql" >/dev/null
for f in "$ROOT"/supabase/migrations/*.sql; do $P -d mg_e2e -f "$f" >/dev/null; done
$P -d mg_e2e -f "$E/seed.sql" >/dev/null 2>&1
echo "βάση mg_e2e έτοιμη"
