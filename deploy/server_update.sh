#!/bin/bash
# BharatPlus CRM - production update script (run ON THE SERVER, as root or with sudo)
#
#   1. Upload the release zip (FTP/SFTP) to the server, e.g. /tmp/bharatplus-release.zip
#   2. unzip -o /tmp/bharatplus-release.zip -d /tmp/bharatplus-release
#   3. Edit the variables below to match the server, then:
#        sudo ODOO_DB=<your_db_name> bash /tmp/bharatplus-release/deploy/server_update.sh
#
set -euo pipefail

# ---- adjust to your server ---------------------------------------------------
ODOO_HOME="${ODOO_HOME:-/odoo}"                       # where odoo-server lives
ODOO_SRC="${ODOO_SRC:-$ODOO_HOME/odoo-server}"        # Odoo 19 source checkout
CUSTOM_ADDONS="${CUSTOM_ADDONS:-$ODOO_HOME/custom/addons}"
ODOO_CONF="${ODOO_CONF:-/etc/odoo-server.conf}"
ODOO_SERVICE="${ODOO_SERVICE:-odoo-server}"           # systemd unit name
ODOO_USER="${ODOO_USER:-odoo}"
PYTHON="${PYTHON:-python3}"                           # or $ODOO_HOME/venv/bin/python
ODOO_DB="${ODOO_DB:?Set ODOO_DB=<database name>}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/odoo}"
# ------------------------------------------------------------------------------

RELEASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "Release: $RELEASE_DIR"
echo "Target : src=$ODOO_SRC addons=$CUSTOM_ADDONS conf=$ODOO_CONF db=$ODOO_DB"

echo "== 1/6 Backup database + filestore"
mkdir -p "$BACKUP_DIR"
STAMP="$(date +%F-%H%M)"
sudo -u postgres pg_dump -Fc "$ODOO_DB" > "$BACKUP_DIR/$ODOO_DB-$STAMP.dump"
DATA_DIR="$(grep -E '^data_dir' "$ODOO_CONF" | sed 's/.*= *//')"
if [ -n "$DATA_DIR" ] && [ -d "$DATA_DIR/filestore/$ODOO_DB" ]; then
  tar -czf "$BACKUP_DIR/$ODOO_DB-filestore-$STAMP.tgz" -C "$DATA_DIR/filestore" "$ODOO_DB"
fi
echo "   backup in $BACKUP_DIR"

echo "== 2/6 Stop Odoo"
systemctl stop "$ODOO_SERVICE"

echo "== 3/6 Copy files"
mkdir -p "$CUSTOM_ADDONS"
cp -r "$RELEASE_DIR/custom/addons/." "$CUSTOM_ADDONS/"
cp -r "$RELEASE_DIR/odoo-server/." "$ODOO_SRC/"          # branding images, /crm URLs, db-manager texts
chown -R "$ODOO_USER":"$ODOO_USER" "$CUSTOM_ADDONS" "$ODOO_SRC/addons/web/static" "$ODOO_SRC/odoo/addons/base/static"

echo "== 4/6 Python dependency (Stripe SDK)"
sudo -u "$ODOO_USER" "$PYTHON" -m pip install --user "stripe==15.6.1" 2>/dev/null \
  || "$PYTHON" -m pip install "stripe==15.6.1"

echo "== 5/6 Install / upgrade modules"
if ! grep -qE "^addons_path.*$CUSTOM_ADDONS" "$ODOO_CONF"; then
  echo "   !! $CUSTOM_ADDONS is not in addons_path of $ODOO_CONF - add it, then re-run"; exit 1
fi
sudo -u "$ODOO_USER" "$PYTHON" "$ODOO_SRC/odoo-bin" -c "$ODOO_CONF" -d "$ODOO_DB" \
  -u crm_dashboard,bharatplus_branding \
  -i bharatplus_subscription,bharatplus_website \
  --stop-after-init

echo "== 6/6 Start Odoo"
systemctl start "$ODOO_SERVICE"
sleep 5
systemctl --no-pager status "$ODOO_SERVICE" | head -5
echo "Done. Now finish deploy/checklist.md (Stripe live keys, webhook, HTTPS)."
