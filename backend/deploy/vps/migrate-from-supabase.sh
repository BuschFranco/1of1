#!/usr/bin/env bash
# Copia los datos de Supabase a la base de la VPS y pasa las fotos de canchas a
# Cloudflare R2. Se corre como root, con una terminal interactiva (pide la contraseña
# de la base de Supabase). Si se corre de nuevo, vuelve a copiar todo desde cero:
# correrlo una última vez justo antes del corte (tanda 2 del README).
#
# Requisitos: las tablas ya creadas (primera publicación con oneofone-deploy) y las
# claves de R2 en /root/.r2-oneofone.env (R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY).
set -euo pipefail

# Proyecto y pooler de Supabase: salen de DIRECT_URL en Render
# (postgresql://postgres.<REF>:<pass>@<HOST>:5432/postgres). Se pueden pasar por env:
#   SUPABASE_REF=<ref> SUPABASE_HOST=<host> bash migrate-from-supabase.sh
# Solo las fotos (no pide contraseña, no toca los datos): SOLO_FOTOS=1 bash migrate-from-supabase.sh
SUPABASE_REF="${SUPABASE_REF:-mwkrsqgdfnfidchotjel}"
# Pooler en modo sesión (IPv4): la conexión directa de Supabase es solo IPv6.
SUPABASE_HOST="${SUPABASE_HOST:-aws-1-sa-east-1.pooler.supabase.com}"
OLD_PREFIX="https://${SUPABASE_REF}.supabase.co/storage/v1/object/public/media/"
NEW_PREFIX="https://img.buschfranco.com/"
ACCOUNT=2e3b069064b630882f2cb54755188225
BUCKET=oneofone-media
DB=oneofone
# En la carpeta de postgres: /root no es legible para el usuario de la base.
DUMP=/var/lib/postgresql/oneofone-supabase.sql
PG17=/usr/lib/postgresql/17/bin

echo "==> Cliente de PostgreSQL 17 (Supabase usa una versión más nueva que la de la VPS)"
[ -x "$PG17/pg_dump" ] || { export DEBIAN_FRONTEND=noninteractive; apt-get -y -q install postgresql-client-17 >/dev/null; }

sudo -u postgres psql -d "$DB" -tAc "select 1 from pg_tables where schemaname = 'public' and tablename = 'users'" | grep -q 1 \
  || { echo "La base $DB no tiene tablas: publicá una versión primero (crea el esquema)."; exit 1; }

if [ "${SOLO_FOTOS:-0}" != 1 ]; then
echo "==> 1) Datos de Supabase"
echo "    Escribí la contraseña de la base de Supabase (Project Settings -> Database) y Enter:"
"$PG17/pg_dump" "host=$SUPABASE_HOST port=5432 dbname=postgres user=postgres.${SUPABASE_REF} sslmode=require" \
  --data-only --schema=public --exclude-table=public._prisma_migrations \
  --disable-triggers --no-owner --no-privileges -f "$DUMP"
# Parámetros que solo existen en Postgres 17: la VPS usa 16.
sed -i '/^SET transaction_timeout/d' "$DUMP"
echo "    $(grep -c '^COPY ' "$DUMP") tablas copiadas de Supabase"

echo "==> 2) Carga en la VPS (vacía las tablas antes, así se puede repetir)"
tables=$(sudo -u postgres psql -d "$DB" -tAc "select string_agg(format('public.%I', tablename), ', ') from pg_tables where schemaname = 'public' and tablename <> '_prisma_migrations'")
sudo -u postgres psql -d "$DB" -v ON_ERROR_STOP=1 -q -c "truncate $tables restart identity cascade"
chown postgres:postgres "$DUMP"
chmod 600 "$DUMP"
sudo -u postgres "$PG17/psql" -d "$DB" -v ON_ERROR_STOP=1 -q -f "$DUMP" >/dev/null
rm -f "$DUMP"
sudo -u postgres psql -d "$DB" -tA -F ': ' -c "
  select 'usuarios', count(*) from users union all
  select 'perfiles', count(*) from profiles union all
  select 'canchas', count(*) from courts union all
  select 'reseñas', count(*) from reviews union all
  select 'pickups', count(*) from pickups union all
  select 'publicaciones', count(*) from court_posts union all
  select 'amistades', count(*) from friends union all
  select 'partidos (ranking)', count(*) from matches union all
  select 'sesiones de juego', count(*) from play_sessions union all
  select 'mensajes', count(*) from messages" | sed 's/^/    /'
fi

echo "==> 3) Fotos: de Supabase Storage (bucket media) a R2 ($BUCKET)"
CREDS=/root/.r2-oneofone.env
[ -f "$CREDS" ] || { echo "Falta $CREDS"; exit 1; }
command -v rclone >/dev/null || curl -fsSL https://rclone.org/install.sh | bash >/dev/null
. <(tr -d '\r' < "$CREDS" | grep -E '^R2_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)=')
export RCLONE_CONFIG_R2O_TYPE=s3 RCLONE_CONFIG_R2O_PROVIDER=Cloudflare RCLONE_CONFIG_R2O_NO_CHECK_BUCKET=true
export RCLONE_CONFIG_R2O_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" RCLONE_CONFIG_R2O_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2O_ENDPOINT="https://${ACCOUNT}.r2.cloudflarestorage.com"
urls=$(sudo -u postgres psql -d "$DB" -tA -c "
  select distinct u from (
    select img as u from courts
    union all select avatar from profiles
  ) x where u like '${OLD_PREFIX}%'")
total=0; ok=0
for url in $urls; do
  total=$((total + 1))
  key="${url#"$OLD_PREFIX"}"
  if rclone copyurl "$url" "r2o:$BUCKET/$key" --header-upload "Cache-Control: public, max-age=31536000, immutable" 2>/dev/null; then
    ok=$((ok + 1))
  else
    echo "    no se pudo copiar: $key"
  fi
done
echo "    $ok de $total fotos copiadas a R2"
[ "$ok" -eq "$total" ] || { echo "Faltan fotos: no se cambian las URLs. Revisá y volvé a correr."; exit 1; }

echo "    Actualizando las URLs de las fotos en la base"
sudo -u postgres psql -d "$DB" -v ON_ERROR_STOP=1 -q <<SQL
update courts set img = replace(img, '${OLD_PREFIX}', '${NEW_PREFIX}') where img like '${OLD_PREFIX}%';
update profiles set avatar = replace(avatar, '${OLD_PREFIX}', '${NEW_PREFIX}') where avatar like '${OLD_PREFIX}%';
SQL

echo
echo "LISTO. Probá: curl https://api.buschfranco.com/health"
