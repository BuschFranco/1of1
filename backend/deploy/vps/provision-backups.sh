#!/usr/bin/env bash
# Backups semanales de la base de 1of1 a Cloudflare R2. Reusa el remoto "r2" y el bucket
# rebound-backups que configuró el provision-backups.sh de Rebound (R2 borra los
# backups a los 90 días). Uso (como root): bash provision-backups.sh
set -euo pipefail

command -v rclone >/dev/null && [ -f /root/.config/rclone/rclone.conf ] \
  || { echo "Falta rclone configurado: correr primero el provision-backups.sh de Rebound"; exit 1; }

echo "==> Script de backup"
cat > /usr/local/bin/oneofone-backup <<'EOF'
#!/usr/bin/env bash
# Copia de la base "oneofone" a R2 (formato custom de pg_dump, ya comprimido).
# Restaurar: rclone copy r2:rebound-backups/oneofone/<archivo> . && sudo -u postgres pg_restore -d oneofone --clean --if-exists <archivo>
set -euo pipefail
stamp=$(date -u +%Y-%m-%dT%H%MZ)
sudo -u postgres pg_dump -d oneofone -Fc | rclone rcat "r2:rebound-backups/oneofone/oneofone-${stamp}.dump"
echo "Backup subido: oneofone/oneofone-${stamp}.dump"
EOF
chmod 750 /usr/local/bin/oneofone-backup

echo "==> Todos los domingos a las 06:15 UTC (03:15 de Argentina, después del de Rebound)"
cat > /etc/systemd/system/oneofone-backup.service <<'EOF'
[Unit]
Description=Backup de la base de 1of1 a Cloudflare R2
After=postgresql.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/oneofone-backup
EOF
cat > /etc/systemd/system/oneofone-backup.timer <<'EOF'
[Unit]
Description=Backup semanal de la base de 1of1

[Timer]
OnCalendar=Sun *-*-* 06:15:00 UTC
Persistent=true
RandomizedDelaySec=10m

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now oneofone-backup.timer >/dev/null

echo "==> Primer backup de prueba"
/usr/local/bin/oneofone-backup
rclone lsl r2:rebound-backups/oneofone/ | tail -n 3
echo
echo "LISTO. Próximo backup: $(systemctl list-timers oneofone-backup.timer --no-pager --no-legend | awk '{print $1, $2, $3}')"
