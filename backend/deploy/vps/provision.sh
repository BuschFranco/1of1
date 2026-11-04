#!/usr/bin/env bash
# Suma el backend de 1of1 a la VPS que ya corre Rebound y el portafolio. Se puede correr
# más de una vez. Requiere que antes se haya corrido el provision.sh de Rebound (Node,
# Caddy, usuario deploy, firewall, swap). No toca las otras apps.
# Uso (como root, desde la carpeta deploy/vps copiada al servidor):
#   bash provision.sh "<clave pública de GitHub Actions de 1of1>"
set -euo pipefail

DEPLOY_PUBKEY="${1:?Falta la clave pública de deploy}"
HERE="$(cd "$(dirname "$0")" && pwd)"

for cmd in node caddy psql; do
  command -v "$cmd" >/dev/null || { echo "Falta $cmd: correr primero los provision de Rebound"; exit 1; }
done
id deploy >/dev/null 2>&1 || { echo "Falta el usuario deploy: correr primero el provision.sh de Rebound"; exit 1; }

echo "==> Usuario 'oneofone' corre el backend; 'deploy' lo publica"
id oneofone >/dev/null 2>&1 || useradd --system --home /srv/oneofone --shell /usr/sbin/nologin oneofone
usermod -aG oneofone deploy
# Se agrega la clave sin pisar las de Rebound y el portafolio.
grep -qxF "$DEPLOY_PUBKEY" /home/deploy/.ssh/authorized_keys 2>/dev/null \
  || echo "$DEPLOY_PUBKEY" >> /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

# releases/<commit> con cada versión, current -> la activa.
install -d -m 2775 -o deploy -g oneofone /srv/oneofone /srv/oneofone/releases /srv/oneofone/incoming

# Variables del backend (DATABASE_URL las escribe provision-db.sh; el resto, a mano).
# El grupo puede leerlas: deploy corre las migraciones con ellas.
install -d -m 750 -o root -g oneofone /etc/oneofone
[ -f /etc/oneofone/oneofone.env ] || install -m 640 -o root -g oneofone /dev/null /etc/oneofone/oneofone.env

echo "==> Script de publicación y permiso para reiniciar solo el backend"
install -m 755 -o root -g root "$HERE/oneofone-deploy" /usr/local/bin/oneofone-deploy
cat > /etc/sudoers.d/oneofone-deploy <<'EOF'
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart oneofone, /usr/bin/systemctl is-active oneofone
EOF
chmod 440 /etc/sudoers.d/oneofone-deploy
visudo -cq

echo "==> Servicio del backend (systemd, puerto 3002)"
cat > /etc/systemd/system/oneofone.service <<'EOF'
[Unit]
Description=1of1 backend (NestJS)
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=oneofone
Group=oneofone
WorkingDirectory=/srv/oneofone/current
EnvironmentFile=/etc/oneofone/oneofone.env
Environment=NODE_ENV=production PORT=3002 HOST=127.0.0.1
ExecStart=/usr/bin/node dist/main.js
Restart=always
RestartSec=3
# La VPS tiene 1 GB y la comparte con Rebound y el portafolio: tope de memoria.
MemoryMax=300M
# Endurecimiento: el backend no escribe en disco (las fotos van a R2).
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable oneofone >/dev/null

echo "==> Caddy: api.buschfranco.com en /etc/caddy/sites"
install -d -m 755 /etc/caddy/sites
install -m 644 "$HERE/api-buschfranco.caddy" /etc/caddy/sites/api-buschfranco.caddy
grep -qF 'import /etc/caddy/sites/*.caddy' /etc/caddy/Caddyfile \
  || printf '\n# Otros sitios de la VPS\nimport /etc/caddy/sites/*.caddy\n' >> /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
systemctl reload caddy

echo
echo "LISTO. Siguiente: bash provision-db.sh, completar /etc/oneofone/oneofone.env y publicar."
