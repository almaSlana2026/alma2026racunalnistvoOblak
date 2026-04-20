#!/usr/bin/env bash
#
# VAJA-07 — stop-vaja07-ec2.sh
# Zaustavi (ne terminate!) vse 3 EC2 instance. VPC, podomrežja, varnostne skupine,
# ključni par in Elastic IP ostanejo. Infrastruktura se ohrani za nadaljevanje
# pri VAJA-08.
#
# Uporaba: ./stop-vaja07-ec2.sh
#
# Avtor: Urban Ambrožič

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/vaja07-state.env"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "Stanje ne obstaja: $STATE_FILE" >&2
    echo "Najprej zaženi data-files/infra-avtomatizacija/create-vaja07-infra.sh." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

echo ">>> Zaustavljanje EC2 instanc ..."
aws ec2 stop-instances --region "$REGION" \
    --instance-ids "$EC2_WEB_ID" "$EC2_DB1_ID" "$EC2_DB2_ID"

echo ">>> Čakam, da so instance v stanju 'stopped' ..."
aws ec2 wait instance-stopped --region "$REGION" \
    --instance-ids "$EC2_WEB_ID" "$EC2_DB1_ID" "$EC2_DB2_ID"

echo ">>> Preverjanje stanja:"
aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$EC2_WEB_ID" "$EC2_DB1_ID" "$EC2_DB2_ID" \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
    --output table

echo ""
echo "Vse 3 instance zaustavljene."
echo "Ohranjeno: VPC $VPC_ID, podomrežja, SG, ključ $KEY_NAME, EIP $EIP_ADDRESS."
