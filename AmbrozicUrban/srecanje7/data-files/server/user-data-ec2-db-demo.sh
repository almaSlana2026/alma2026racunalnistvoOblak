#!/bin/bash
#
# VAJA-07 — user-data skripta za EC2-3 (demo DB).
# Cloud-init jo zažene ob prvem zagonu instance kot root, samodejno in neinteraktivno.
# Namen: prikaz, da lahko podatkovni strežnik namestimo že pri izdelavi EC2 (via user-data).
#
# Avtor: Urban Ambrožič

set -eux

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y mariadb-server
systemctl enable --now mariadb

echo "VAJA-07 user-data končan ob $(date -Iseconds)" > /var/log/vaja07-user-data.log
