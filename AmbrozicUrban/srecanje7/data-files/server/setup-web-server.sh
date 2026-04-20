#!/usr/bin/env bash
#
# VAJA-07 — setup-web-server.sh
# Namesti Apache, PHP in MariaDB klient na EC2-1 ter objavi spletno aplikacijo
# (index.html, vstavi.php, izpis.php, db.php) v /var/www/html/.
#
# Uporaba: na EC2-1, iz iste mape, kjer ležijo tudi datoteke spletne aplikacije:
#   sudo bash setup-web-server.sh
#
# Avtor: Urban Ambrožič

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_ROOT="/var/www/html"

echo ">>> [1/5] apt update"
sudo apt-get update -y

echo ">>> [2/5] apt install apache2 php php-mysqli mariadb-client"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2 php php-mysqli mariadb-client

echo ">>> [3/5] Omogočanje in zagon Apache"
sudo systemctl enable --now apache2

echo ">>> [4/5] Objava aplikacije v ${WEB_ROOT}"
sudo rm -f "${WEB_ROOT}/index.html"
sudo cp -v "${SCRIPT_DIR}/index.html"  "${WEB_ROOT}/index.html"
sudo cp -v "${SCRIPT_DIR}/vstavi.php"  "${WEB_ROOT}/vstavi.php"
sudo cp -v "${SCRIPT_DIR}/izpis.php"   "${WEB_ROOT}/izpis.php"
sudo cp -v "${SCRIPT_DIR}/db.php"      "${WEB_ROOT}/db.php"
sudo cp -v "${SCRIPT_DIR}/styles.css"  "${WEB_ROOT}/styles.css"
sudo chown -R www-data:www-data "${WEB_ROOT}"

echo ">>> [5/5] Preverjanje"
systemctl is-active apache2
php -v | head -1
echo "Web setup končan. Aplikacija na http://<EIP>/"
