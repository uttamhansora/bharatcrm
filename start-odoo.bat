@echo off
cd /d C:\xampp\htdocs\bharatcrm
echo Starting Bharatplus CRM on http://127.0.0.1:8069 ...
venv\Scripts\python.exe odoo-server\odoo-bin -c odoo.conf
