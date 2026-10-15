# BharatPlus CRM — go-live checklist

## A. Before uploading
- [ ] Server has Odoo 19 (same commit `1c863507`, branch 19.0) at `/odoo/odoo-server`, PostgreSQL, Python 3.11+.
- [ ] You have **SSH** (FTP alone cannot install the Stripe SDK, run the module upgrade or restart Odoo).
- [ ] Decide the database name (e.g. `bharatplus`) and your domain (e.g. `crm.bharatplus.co`), DNS A record → server IP.

## B. Upload (FTP/SFTP)
- [ ] Upload `bharatplus-release-<date>.zip` to `/tmp` on the server.
- [ ] `unzip -o /tmp/bharatplus-release-<date>.zip -d /tmp/bharatplus-release`

## C. Run the update (SSH)
```bash
sudo ODOO_DB=bharatplus ODOO_HOME=/odoo ODOO_CONF=/etc/odoo-server.conf ODOO_SERVICE=odoo-server \
     bash /tmp/bharatplus-release/deploy/server_update.sh
```
It backs up DB + filestore, copies the modules and core files, installs `stripe`, runs
`-u crm_dashboard,bharatplus_branding -i bharatplus_subscription,bharatplus_website`, restarts Odoo.
(If `/odoo/custom/addons` is not yet in `addons_path`, add it to the conf first.)

## D. Configuration (`/etc/odoo-server.conf`, see `odoo-server.conf.example`)
- [ ] `admin_passwd` = long random value (the old `admin` is how databases get dropped)
- [ ] `list_db = False`, `dbfilter = ^bharatplus$`
- [ ] `proxy_mode = True`, `workers = 2*CPU+1`, `http_interface = 127.0.0.1`
- [ ] nginx + HTTPS (`nginx-bharatplus.conf.example`, `certbot --nginx -d <domain>`), DB manager blocked
- [ ] Settings → Technical → System Parameters → `web.base.url = https://<domain>` (and `web.base.url.freeze = True`)
- [ ] Settings → Technical → Outgoing Mail Servers (needed for team-member invitation e-mails & password resets)

## E. Stripe (LIVE)
- [ ] Stripe Dashboard → switch to **Live** → copy `sk_live_…` / `pk_live_…`
- [ ] Settings → BharatPlus Subscription → paste keys → **Create Product & Price in Stripe** (creates the live ₹400/month price; the test price id is not valid in live mode)
- [ ] Developers → Webhooks → Add endpoint `https://<domain>/bharatplus/stripe/webhook`, events:
      `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`,
      `customer.subscription.trial_will_end`, `invoice.paid`, `invoice.payment_failed`, `checkout.session.completed`
      → paste the signing secret into Settings → BharatPlus Subscription
- [ ] Settings → Billing → Customer portal: enabled (payment method update, invoice history)
- [ ] Complete Stripe account activation (business details, bank account, INR payouts)
- [ ] Rotate/delete the TEST keys that were shared in chat

## F. Smoke test on production
- [ ] `https://<domain>/` home, `/pricing`, `/about`, `/contact` load; header **Login** works
- [ ] Sign up with Company Name → trial confirmation → start → lands in CRM (Leads)
- [ ] CRM → Configuration → Team Members → Invite → Stripe quantity +1 (Settings → Subscription shows ₹ amount)
- [ ] Add Payment Method (real card in live mode, or stay in test mode first)
- [ ] `/odoo` redirects to `/crm`; `/web/database/manager` is blocked from the internet

## G. Backups & monitoring (do not skip — this is what was missing before)
- [ ] Nightly `pg_dump -Fc` + filestore tar to off-server storage (S3/Backblaze/Drive), 30-day retention
- [ ] Test a restore once
- [ ] Log rotation (`logrotate = True`), PostgreSQL `log_statement = 'ddl'`
- [ ] Uptime monitor on `https://<domain>/web/login`
