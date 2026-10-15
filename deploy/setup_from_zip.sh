#!/bin/bash
# BharatPlus CRM - first-time setup on a Linux server from the extracted bharatcrm folder.
#
#   sudo APP_DIR=/opt/bharatcrm DOMAIN=crm.bharatplus.co bash /opt/bharatcrm/deploy/setup_from_zip.sh
#
# Optional: RESTORE_DUMP=/tmp/bharatcrm.dump  (pg_dump -Fc of your local DB) to restore instead of a fresh DB.
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/bharatcrm}"
DB_NAME="${DB_NAME:-bharatplus}"
DB_USER="${DB_USER:-odoo}"
DB_PASS="${DB_PASS:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)}"
ADMIN_PASS="${ADMIN_PASS:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)}"
SYS_USER="${SYS_USER:-odoo}"
DOMAIN="${DOMAIN:-}"
RESTORE_DUMP="${RESTORE_DUMP:-}"
CONF="/etc/bharatcrm.conf"

echo "== 1/7 System packages"
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip python3-dev build-essential \
  postgresql postgresql-client libpq-dev libxml2-dev libxslt1-dev libldap2-dev libsasl2-dev \
  libjpeg-dev zlib1g-dev libffi-dev libssl-dev node-less npm unzip git nginx >/dev/null
id -u "$SYS_USER" >/dev/null 2>&1 || useradd -r -m -d /var/lib/odoo -s /bin/bash "$SYS_USER"

echo "== 2/7 Clean Windows leftovers + Python virtualenv"
cd "$APP_DIR"
rm -rf venv odoo-local.zip logs/*.log .local
find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
python3 -m venv venv
venv/bin/pip install -q --upgrade pip wheel
venv/bin/pip install -q -r odoo-server/requirements.txt "stripe==15.6.1"
mkdir -p data logs
chown -R "$SYS_USER":"$SYS_USER" "$APP_DIR"

echo "== 3/7 PostgreSQL role + database"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE ROLE $DB_USER LOGIN CREATEDB PASSWORD '$DB_PASS';"
sudo -u postgres psql -c "ALTER ROLE $DB_USER PASSWORD '$DB_PASS';" >/dev/null
if ! sudo -u postgres psql -lqt | cut -d'|' -f1 | grep -qw "$DB_NAME"; then
  sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"
  if [ -n "$RESTORE_DUMP" ]; then
    echo "   restoring $RESTORE_DUMP"
    sudo -u postgres pg_restore -d "$DB_NAME" --no-owner --role="$DB_USER" "$RESTORE_DUMP"
    # filestore of the local db was named bharatcrm
    [ -d "$APP_DIR/data/filestore/bharatcrm" ] && [ ! -d "$APP_DIR/data/filestore/$DB_NAME" ] \
      && mv "$APP_DIR/data/filestore/bharatcrm" "$APP_DIR/data/filestore/$DB_NAME"
    FRESH=0
  else
    FRESH=1
  fi
else
  echo "   database $DB_NAME already exists - keeping it"; FRESH=0
fi

echo "== 4/7 Config $CONF"
cat > "$CONF" <<EOF
[options]
admin_passwd = $ADMIN_PASS
list_db = False
dbfilter = ^$DB_NAME\$
db_host = 127.0.0.1
db_port = 5432
db_user = $DB_USER
db_password = $DB_PASS
db_name = $DB_NAME
db_maxconn = 64
addons_path = $APP_DIR/odoo-server/odoo/addons,$APP_DIR/odoo-server/addons,$APP_DIR/custom/addons
data_dir = $APP_DIR/data
logfile = $APP_DIR/logs/odoo.log
log_level = info
logrotate = True
http_interface = 127.0.0.1
http_port = 8069
gevent_port = 8072
proxy_mode = True
workers = $(( 2 * $(nproc) + 1 ))
max_cron_threads = 1
limit_time_cpu = 600
limit_time_real = 1200
without_demo = True
EOF
chown "$SYS_USER":"$SYS_USER" "$CONF"; chmod 640 "$CONF"

echo "== 5/7 Database init / module upgrade"
if [ "$FRESH" = "1" ]; then
  sudo -u "$SYS_USER" "$APP_DIR/venv/bin/python" "$APP_DIR/odoo-server/odoo-bin" -c "$CONF" -d "$DB_NAME" \
    -i base,crm,sale_management,contacts,calendar,bharatplus_branding,bharatplus_subscription,bharatplus_website \
    --without-demo=all --stop-after-init
else
  sudo -u "$SYS_USER" "$APP_DIR/venv/bin/python" "$APP_DIR/odoo-server/odoo-bin" -c "$CONF" -d "$DB_NAME" \
    -u bharatplus_branding,bharatplus_subscription,bharatplus_website --stop-after-init
fi

echo "== 6/7 systemd service"
cat > /etc/systemd/system/bharatcrm.service <<EOF
[Unit]
Description=BharatPlus CRM (Odoo 19)
After=network.target postgresql.service

[Service]
Type=simple
User=$SYS_USER
Group=$SYS_USER
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/odoo-server/odoo-bin -c $CONF
Restart=always
RestartSec=5
# Optional: Stripe keys as environment variables instead of the Settings page
# Environment=STRIPE_SECRET_KEY=sk_live_...
# Environment=STRIPE_WEBHOOK_SECRET=whsec_...

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now bharatcrm
sleep 5; systemctl --no-pager status bharatcrm | head -3

echo "== 7/7 nginx"
if [ -n "$DOMAIN" ]; then
  sed "s/crm.bharatplus.co/$DOMAIN/g" "$APP_DIR/deploy/nginx-bharatplus.conf.example" > /etc/nginx/sites-available/bharatcrm
  ln -sf /etc/nginx/sites-available/bharatcrm /etc/nginx/sites-enabled/bharatcrm
  rm -f /etc/nginx/sites-enabled/default
  # start with plain http until certbot installs the certificate
  sed -i 's/listen 443 ssl http2;/listen 443 ssl http2; ssl_certificate \/etc\/ssl\/certs\/ssl-cert-snakeoil.pem; ssl_certificate_key \/etc\/ssl\/private\/ssl-cert-snakeoil.key;/' /etc/nginx/sites-available/bharatcrm
  nginx -t && systemctl reload nginx
  echo "   next: apt-get install -y certbot python3-certbot-nginx && certbot --nginx -d $DOMAIN"
fi

cat <<EOF

================= DONE =================
URL (via nginx)   : http://$DOMAIN/   (then run certbot for https)
Local check       : curl -I http://127.0.0.1:8069/web/login
Config            : $CONF
Master password   : $ADMIN_PASS      <- store it in a password manager
DB user/password  : $DB_USER / $DB_PASS
Service           : systemctl restart bharatcrm   |  journalctl -u bharatcrm -f  |  $APP_DIR/logs/odoo.log
Login             : $( [ "$FRESH" = "1" ] && echo "admin / admin  -> change it immediately" || echo "same users as the restored database" )
Then follow deploy/checklist.md (Stripe live keys, webhook, backups).
========================================
EOF
