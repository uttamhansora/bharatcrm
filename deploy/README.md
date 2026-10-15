# BharatPlus CRM — release package

Contents of `bharatplus-release-<date>.zip`:

| Path | What |
|---|---|
| `custom/addons/bharatplus_branding/` | White-label (Bharatplus name/logo, `/crm` URLs, Apps page, settings texts) |
| `custom/addons/bharatplus_subscription/` | Stripe billing: 1-month trial, ₹400/member/month, business signup, team members, webhook |
| `custom/addons/bharatplus_website/` | Public site: Home, Pricing (calculator + Start Free Trial), About, Contact |
| `custom/addons/crm_dashboard/` | Existing module with Odoo-19 compatibility fixes |
| `odoo-server/...` | 13 Odoo core files (`/odoo` → `/crm` URL prefix, database-manager texts) + 12 brand images |
| `deploy/odoo-core-bharatplus.patch` | The same core changes as a `git apply` patch (alternative to copying files) |
| `deploy/server_update.sh` | One-shot server script: backup → copy → `pip install stripe` → install/upgrade modules → restart |
| `deploy/odoo-server.conf.example` | Hardened production config |
| `deploy/nginx-bharatplus.conf.example` | HTTPS reverse proxy, websocket, DB manager blocked |
| `deploy/checklist.md` | Go-live checklist (Stripe live keys, webhook, backups) |
| `deploy/stripe.env.example` | Environment-variable alternative for the Stripe keys |

## Why FTP alone is not enough
Odoo is a running Python service, not static files. After uploading you must (over SSH):
install the `stripe` Python package, run the module install/upgrade (`odoo-bin -i/-u`), and
restart the `odoo-server` service. `server_update.sh` does all of that.

## Alternative to FTP: git
`custom/addons` is the GitHub repo `Bharat-CRM-plus/backend`. Committing the three
`bharatplus_*` modules there and running `git pull` on the server is safer and repeatable.
The core changes still need the patch: `cd /odoo/odoo-server && git apply /tmp/bharatplus-release/deploy/odoo-core-bharatplus.patch`.

## Local dev reference
Windows: `start-odoo.bat`; tests:
`python odoo-bin -c odoo.conf -d bharatcrm -u bharatplus_subscription,bharatplus_website --test-enable --test-tags bharatplus_subscription,bharatplus_website --stop-after-init`
