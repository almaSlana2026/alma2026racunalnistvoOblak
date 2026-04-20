#!/usr/bin/env bash
#
# VAJA-07 — Kreiranje AWS infrastrukture za varno spletno rešitev z več
# podomrežji v različnih Availability Zone:
#
#   VPC 192.168.0.0/24
#     ├─ Sub1 (javno, 192.168.0.0/25,   AZ-a) — EC2-1 web
#     ├─ Sub2 (privatno, 192.168.0.128/26, AZ-b) — EC2-2 glavni DB
#     └─ Sub3 (privatno, 192.168.0.192/27, AZ-c) — EC2-3 demo DB (user-data)
#
#   IGW → public RT (0.0.0.0/0 → IGW), private RT (brez privzete poti).
#   SG-web: 22/80 iz 0.0.0.0/0.  SG-db: 22 + 3306 iz sg-web.
#   1 skupni ključni par za vse 3 EC2. Elastic IP za EC2-1.
#
# Med postavitvijo so Sub1 + Sub2 + Sub3 asociirani s public RT (za apt/user-data).
# Po koncu faze 5 (ročno) se Sub2 in Sub3 prevežeta na private RT.
#
# Uporaba: ./create-vaja07-infra.sh
# Stanje se zapiše v ../../vaja07-state.env (bere ga stop-vaja07-ec2.sh).
#
# Avtor: Urban Ambrožič

set -euo pipefail

PREFIX="vaja07"
REGION="eu-central-1"
VPC_CIDR="192.168.0.0/24"
SUB1_CIDR="192.168.0.0/25"      # 128 naslovov, javno podomrežje
SUB2_CIDR="192.168.0.128/26"    # 64 naslovov, privatno podomrežje
SUB3_CIDR="192.168.0.192/27"    # 32 naslovov, privatno podomrežje
INSTANCE_TYPE="t3.micro"
KEY_NAME="${PREFIX}-key"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
KEY_FILE="${ROOT_DIR}/${KEY_NAME}.pem"
STATE_FILE="${ROOT_DIR}/${PREFIX}-state.env"
USER_DATA_FILE="${SCRIPT_DIR}/../server/user-data-ec2-db-demo.sh"

tag_spec() {
    local rtype="$1" name="$2"
    echo "ResourceType=${rtype},Tags=[{Key=Name,Value=${name}}]"
}

echo ">>> [1/17] Iskanje najnovejšega Debian 12 AMI v ${REGION}"
AMI_ID=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners 136693071363 \
    --filters "Name=name,Values=debian-12-amd64-*" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)
echo "    AMI: $AMI_ID"

echo ">>> [2/17] Ustvarjanje VPC ${VPC_CIDR}"
VPC_ID=$(aws ec2 create-vpc \
    --region "$REGION" \
    --cidr-block "$VPC_CIDR" \
    --tag-specifications "$(tag_spec vpc ${PREFIX}-vpc)" \
    --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames
echo "    VPC: $VPC_ID"

echo ">>> [3/17] Branje treh Availability Zone"
mapfile -t AZS < <(aws ec2 describe-availability-zones --region "$REGION" \
    --query 'AvailabilityZones[].ZoneName' --output text | tr '\t' '\n')
AZ1="${AZS[0]}"
AZ2="${AZS[1]}"
AZ3="${AZS[2]}"
echo "    AZ1=$AZ1  AZ2=$AZ2  AZ3=$AZ3"

echo ">>> [4/17] Ustvarjanje Sub1 (javno, ${SUB1_CIDR}, ${AZ1})"
SUB1_ID=$(aws ec2 create-subnet --region "$REGION" \
    --vpc-id "$VPC_ID" --cidr-block "$SUB1_CIDR" --availability-zone "$AZ1" \
    --tag-specifications "$(tag_spec subnet ${PREFIX}-subnet-public)" \
    --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --region "$REGION" \
    --subnet-id "$SUB1_ID" --map-public-ip-on-launch
echo "    Sub1: $SUB1_ID"

echo ">>> [5/17] Ustvarjanje Sub2 (privatno, ${SUB2_CIDR}, ${AZ2})"
SUB2_ID=$(aws ec2 create-subnet --region "$REGION" \
    --vpc-id "$VPC_ID" --cidr-block "$SUB2_CIDR" --availability-zone "$AZ2" \
    --tag-specifications "$(tag_spec subnet ${PREFIX}-subnet-db-primary)" \
    --query 'Subnet.SubnetId' --output text)
# Začasno map-public-ip za setup fazo; po končanem delu to vrnemo nazaj.
aws ec2 modify-subnet-attribute --region "$REGION" \
    --subnet-id "$SUB2_ID" --map-public-ip-on-launch
echo "    Sub2: $SUB2_ID"

echo ">>> [6/17] Ustvarjanje Sub3 (privatno, ${SUB3_CIDR}, ${AZ3})"
SUB3_ID=$(aws ec2 create-subnet --region "$REGION" \
    --vpc-id "$VPC_ID" --cidr-block "$SUB3_CIDR" --availability-zone "$AZ3" \
    --tag-specifications "$(tag_spec subnet ${PREFIX}-subnet-db-demo)" \
    --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --region "$REGION" \
    --subnet-id "$SUB3_ID" --map-public-ip-on-launch
echo "    Sub3: $SUB3_ID"

echo ">>> [7/17] Ustvarjanje in pripenjanje Internet Gateway"
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" \
    --tag-specifications "$(tag_spec internet-gateway ${PREFIX}-igw)" \
    --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --region "$REGION" \
    --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
echo "    IGW: $IGW_ID"

echo ">>> [8/17] Ustvarjanje public route table (0.0.0.0/0 → IGW)"
RTB_PUB_ID=$(aws ec2 create-route-table --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "$(tag_spec route-table ${PREFIX}-rt-public)" \
    --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region "$REGION" \
    --route-table-id "$RTB_PUB_ID" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID" > /dev/null
echo "    Public RT: $RTB_PUB_ID"

echo ">>> [9/17] Ustvarjanje private route table (brez privzete poti)"
RTB_PRIV_ID=$(aws ec2 create-route-table --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "$(tag_spec route-table ${PREFIX}-rt-private)" \
    --query 'RouteTable.RouteTableId' --output text)
echo "    Private RT: $RTB_PRIV_ID"

echo ">>> [10/17] Začasne asociacije RT: Sub1 + Sub2 + Sub3 → public"
ASSOC1_ID=$(aws ec2 associate-route-table --region "$REGION" \
    --route-table-id "$RTB_PUB_ID" --subnet-id "$SUB1_ID" \
    --query 'AssociationId' --output text)
ASSOC2_ID=$(aws ec2 associate-route-table --region "$REGION" \
    --route-table-id "$RTB_PUB_ID" --subnet-id "$SUB2_ID" \
    --query 'AssociationId' --output text)
ASSOC3_ID=$(aws ec2 associate-route-table --region "$REGION" \
    --route-table-id "$RTB_PUB_ID" --subnet-id "$SUB3_ID" \
    --query 'AssociationId' --output text)
echo "    Assoc: Sub1=$ASSOC1_ID  Sub2=$ASSOC2_ID  Sub3=$ASSOC3_ID"

echo ">>> [11/17] Ustvarjanje SG ${PREFIX}-sg-web (22, 80 iz 0.0.0.0/0)"
SG_WEB_ID=$(aws ec2 create-security-group --region "$REGION" \
    --group-name "${PREFIX}-sg-web" \
    --description "VAJA-07 web tier: SSH + HTTP" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "$(tag_spec security-group ${PREFIX}-sg-web)" \
    --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_WEB_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_WEB_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
echo "    SG web: $SG_WEB_ID"

echo ">>> [12/17] Ustvarjanje SG ${PREFIX}-sg-db (22 + 3306 iz sg-web)"
SG_DB_ID=$(aws ec2 create-security-group --region "$REGION" \
    --group-name "${PREFIX}-sg-db" \
    --description "VAJA-07 db tier: MariaDB + bastion SSH iz sg-web" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "$(tag_spec security-group ${PREFIX}-sg-db)" \
    --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_DB_ID" --protocol tcp --port 22 \
    --source-group "$SG_WEB_ID" > /dev/null
aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_DB_ID" --protocol tcp --port 3306 \
    --source-group "$SG_WEB_ID" > /dev/null
echo "    SG db:  $SG_DB_ID"

echo ">>> [13/17] Ustvarjanje ključnega para ${KEY_NAME}"
if [[ -f "$KEY_FILE" ]]; then
    echo "    Lokalni $KEY_FILE že obstaja — izbriši ali preimenuj, preden ponovno poganjaš." >&2
    exit 1
fi
aws ec2 create-key-pair --region "$REGION" \
    --key-name "$KEY_NAME" \
    --tag-specifications "$(tag_spec key-pair ${PREFIX}-key)" \
    --query 'KeyMaterial' --output text > "$KEY_FILE"
chmod 400 "$KEY_FILE" 2>/dev/null || true
echo "    Ključ shranjen: $KEY_FILE"

echo ">>> [14/17] Zaganjanje EC2-1 (web, Sub1, sg-web)"
EC2_WEB_ID=$(aws ec2 run-instances --region "$REGION" \
    --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUB1_ID" --security-group-ids "$SG_WEB_ID" \
    --tag-specifications "$(tag_spec instance ${PREFIX}-ec2-web)" \
    --query 'Instances[0].InstanceId' --output text)
echo "    EC2-1: $EC2_WEB_ID"

echo ">>> [15/17] Zaganjanje EC2-2 (db-primary, Sub2, sg-db)"
EC2_DB1_ID=$(aws ec2 run-instances --region "$REGION" \
    --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUB2_ID" --security-group-ids "$SG_DB_ID" \
    --tag-specifications "$(tag_spec instance ${PREFIX}-ec2-db-primary)" \
    --query 'Instances[0].InstanceId' --output text)
echo "    EC2-2: $EC2_DB1_ID"

echo ">>> [16/17] Zaganjanje EC2-3 (db-demo, Sub3, sg-db, user-data)"
if [[ ! -f "$USER_DATA_FILE" ]]; then
    echo "    User-data datoteka ne obstaja: $USER_DATA_FILE" >&2
    exit 1
fi
EC2_DB2_ID=$(aws ec2 run-instances --region "$REGION" \
    --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUB3_ID" --security-group-ids "$SG_DB_ID" \
    --user-data "file://${USER_DATA_FILE}" \
    --tag-specifications "$(tag_spec instance ${PREFIX}-ec2-db-demo)" \
    --query 'Instances[0].InstanceId' --output text)
echo "    EC2-3: $EC2_DB2_ID"

echo ">>> [17/17] Čakam da so vse 3 instance running + dodelitev EIP + branje IP + stanje"
aws ec2 wait instance-running --region "$REGION" \
    --instance-ids "$EC2_WEB_ID" "$EC2_DB1_ID" "$EC2_DB2_ID"

EIP_ALLOC_ID=$(aws ec2 allocate-address --region "$REGION" \
    --domain vpc \
    --tag-specifications "$(tag_spec elastic-ip ${PREFIX}-eip)" \
    --query 'AllocationId' --output text)
EIP_ADDRESS=$(aws ec2 describe-addresses --region "$REGION" \
    --allocation-ids "$EIP_ALLOC_ID" \
    --query 'Addresses[0].PublicIp' --output text)
aws ec2 associate-address --region "$REGION" \
    --allocation-id "$EIP_ALLOC_ID" \
    --instance-id "$EC2_WEB_ID" > /dev/null

EC2_WEB_PRIV_IP=$(aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$EC2_WEB_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
EC2_DB1_PRIV_IP=$(aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$EC2_DB1_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
EC2_DB1_PUB_IP=$(aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$EC2_DB1_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
EC2_DB2_PRIV_IP=$(aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$EC2_DB2_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
EC2_DB2_PUB_IP=$(aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$EC2_DB2_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

cat > "$STATE_FILE" <<EOF
# VAJA-07 — stanje infrastrukture (generirano $(date -Iseconds))
REGION=$REGION
VPC_ID=$VPC_ID
SUB1_ID=$SUB1_ID
SUB2_ID=$SUB2_ID
SUB3_ID=$SUB3_ID
AZ1=$AZ1
AZ2=$AZ2
AZ3=$AZ3
IGW_ID=$IGW_ID
RTB_PUB_ID=$RTB_PUB_ID
RTB_PRIV_ID=$RTB_PRIV_ID
ASSOC1_ID=$ASSOC1_ID
ASSOC2_ID=$ASSOC2_ID
ASSOC3_ID=$ASSOC3_ID
SG_WEB_ID=$SG_WEB_ID
SG_DB_ID=$SG_DB_ID
KEY_NAME=$KEY_NAME
KEY_FILE=$KEY_FILE
EC2_WEB_ID=$EC2_WEB_ID
EC2_DB1_ID=$EC2_DB1_ID
EC2_DB2_ID=$EC2_DB2_ID
EIP_ALLOC_ID=$EIP_ALLOC_ID
EIP_ADDRESS=$EIP_ADDRESS
EC2_WEB_PRIV_IP=$EC2_WEB_PRIV_IP
EC2_DB1_PRIV_IP=$EC2_DB1_PRIV_IP
EC2_DB1_PUB_IP=$EC2_DB1_PUB_IP
EC2_DB2_PRIV_IP=$EC2_DB2_PRIV_IP
EC2_DB2_PUB_IP=$EC2_DB2_PUB_IP
AMI_ID=$AMI_ID
EOF

echo ""
echo "========================================="
echo "Infrastruktura pripravljena."
echo "  EC2-1 (web):        $EC2_WEB_ID"
echo "     EIP:             $EIP_ADDRESS"
echo "     privatni IP:     $EC2_WEB_PRIV_IP"
echo "  EC2-2 (db-primary): $EC2_DB1_ID"
echo "     privatni IP:     $EC2_DB1_PRIV_IP"
echo "     začasni javni:   $EC2_DB1_PUB_IP"
echo "  EC2-3 (db-demo):    $EC2_DB2_ID"
echo "     privatni IP:     $EC2_DB2_PRIV_IP"
echo "     začasni javni:   $EC2_DB2_PUB_IP"
echo ""
echo "  SSH na EC2-1:  ssh -i $KEY_FILE admin@$EIP_ADDRESS"
echo "  Stanje:         $STATE_FILE"
echo "========================================="
