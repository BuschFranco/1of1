#!/usr/bin/env bash
# Base de 1of1 en el PostgreSQL 16 que ya corre en la VPS (lo instaló el provision-db.sh
# de Rebound). Se puede correr más de una vez. Uso (como root): bash provision-db.sh
#
# Solo crea la base y su rol. Las TABLAS las crea `prisma migrate deploy` en cada
# publicación (oneofone-deploy), igual que hacía Render al arrancar. El rol es dueño
# de las tablas, así que el RLS de la migración enable_rls no lo frena (como en Supabase).
set -euo pipefail

DB=oneofone
KEYS=/root/oneofone-db.env   # contraseña generada una sola vez; solo root
ENV_FILE=/etc/oneofone/oneofone.env

command -v psql >/dev/null || { echo "Falta PostgreSQL: correr primero el provision-db.sh de Rebound"; exit 1; }
[ -f "$ENV_FILE" ] || { echo "Falta $ENV_FILE: correr primero provision.sh"; exit 1; }

echo "==> Contraseña del rol (se genera una sola vez)"
if [ ! -f "$KEYS" ]; then
  umask 077
  echo "DB_PASSWORD=$(openssl rand -hex 24)" > "$KEYS"
fi
# shellcheck disable=SC1090
. "$KEYS"

echo "==> Rol y base"
sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<SQL
do \$\$ begin
  if not exists (select from pg_roles where rolname = '$DB') then create role $DB login; end if;
end \$\$;
alter role $DB password '${DB_PASSWORD}';
SQL
sudo -u postgres psql -tAc "select 1 from pg_database where datname = '$DB'" | grep -q 1 \
  || sudo -u postgres createdb -O "$DB" "$DB"
# Nadie más se conecta a esta base (los roles de PostgREST de Rebound tampoco).
sudo -u postgres psql -v ON_ERROR_STOP=1 -q -c "revoke connect on database $DB from public"
sudo -u postgres psql -d "$DB" -v ON_ERROR_STOP=1 -q -c "alter schema public owner to $DB"

echo "==> DATABASE_URL / DIRECT_URL en $ENV_FILE"
URL="postgresql://${DB}:${DB_PASSWORD}@127.0.0.1:5432/${DB}"
for key in DATABASE_URL DIRECT_URL; do
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${URL}|" "$ENV_FILE"
  else
    echo "${key}=${URL}" >> "$ENV_FILE"
  fi
done

echo "==> Prueba"
PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -U "$DB" -d "$DB" -tAc "select 'conexión ok: ' || current_user"
echo
echo "LISTO. Las tablas se crean en la primera publicación (prisma migrate deploy)."
