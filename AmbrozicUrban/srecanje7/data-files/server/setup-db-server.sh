#!/usr/bin/env bash
#
# VAJA-07 — setup-db-server.sh
# Namesti MariaDB strežnik na EC2-2, nastavi poslušanje na vseh vmesnikih
# (bind-address=0.0.0.0) in uvozi shemo + testne podatke iz setup-db.sql.
#
# Uporaba: na EC2-2, iz iste mape, kjer leži tudi setup-db.sql:
#   sudo bash setup-db-server.sh
#
# Avtor: Urban Ambrožič

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="${SCRIPT_DIR}/setup-db.sql"

if [[ ! -f "$SQL_FILE" ]]; then
    echo "setup-db.sql ne obstaja v $SCRIPT_DIR" >&2
    exit 1
fi

echo ">>> [1/5] apt update"
sudo apt-get update -y

echo ">>> [2/5] apt install mariadb-server"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server

echo ">>> [3/5] Nastavitev bind-address=0.0.0.0 v /etc/mysql/mariadb.conf.d/50-server.cnf"
sudo sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' \
    /etc/mysql/mariadb.conf.d/50-server.cnf

echo ">>> [4/5] Omogočanje in restart MariaDB"
sudo systemctl enable --now mariadb
sudo systemctl restart mariadb
systemctl is-active mariadb

echo ">>> [5/5] Uvoz sheme in testnih podatkov iz setup-db.sql"
sudo mariadb < "$SQL_FILE"

echo ""
echo "DB setup končan. Vsebina tabele nakup:"
mariadb -u urban -purban -e "SELECT * FROM AlmaMater.nakup;"
