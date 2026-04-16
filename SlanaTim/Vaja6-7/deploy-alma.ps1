# =========================
# AWS INFRA SETUP - ALMAMATER WITH NAT
# =========================

# ---------- SETTINGS ----------
$REGION = "eu-central-1"
$MY_IP = "IP"
$KEY_NAME = "alma-key-4"
$AMI_ID = "ami-02daa6fa3fe5f3161"
$INSTANCE_TYPE = "t3.small"

# ---------- 1. CREATE VPC ----------
$VPC_ID = aws ec2 create-vpc `
  --region $REGION `
  --cidr-block 192.168.0.0/24 `
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=alma-vpc}]" `
  --query "Vpc.VpcId" `
  --output text

Write-Host "VPC created: $VPC_ID"

aws ec2 modify-vpc-attribute --region $REGION --vpc-id $VPC_ID --enable-dns-support
aws ec2 modify-vpc-attribute --region $REGION --vpc-id $VPC_ID --enable-dns-hostnames

# ---------- 2. CREATE SUBNETS ----------
$SUB1_ID = aws ec2 create-subnet `
  --region $REGION `
  --vpc-id $VPC_ID `
  --cidr-block 192.168.0.0/25 `
  --availability-zone "${REGION}a" `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=alma-sub1-public}]" `
  --query "Subnet.SubnetId" `
  --output text

$SUB2_ID = aws ec2 create-subnet `
  --region $REGION `
  --vpc-id $VPC_ID `
  --cidr-block 192.168.0.128/26 `
  --availability-zone "${REGION}b" `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=alma-sub2-private}]" `
  --query "Subnet.SubnetId" `
  --output text

$SUB3_ID = aws ec2 create-subnet `
  --region $REGION `
  --vpc-id $VPC_ID `
  --cidr-block 192.168.0.192/27 `
  --availability-zone "${REGION}c" `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=alma-sub3-private}]" `
  --query "Subnet.SubnetId" `
  --output text

Write-Host "Subnets created:"
Write-Host "Public:  $SUB1_ID"
Write-Host "Private: $SUB2_ID"
Write-Host "Private: $SUB3_ID"

# make subnet1 public
aws ec2 modify-subnet-attribute `
  --region $REGION `
  --subnet-id $SUB1_ID `
  --map-public-ip-on-launch

# ---------- 3. INTERNET GATEWAY ----------
$IGW_ID = aws ec2 create-internet-gateway `
  --region $REGION `
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=alma-igw}]" `
  --query "InternetGateway.InternetGatewayId" `
  --output text

aws ec2 attach-internet-gateway `
  --region $REGION `
  --internet-gateway-id $IGW_ID `
  --vpc-id $VPC_ID

Write-Host "IGW created: $IGW_ID"

# ---------- 4. PUBLIC ROUTE TABLE ----------
$RT_PUBLIC = aws ec2 create-route-table `
  --region $REGION `
  --vpc-id $VPC_ID `
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=alma-rt-public}]" `
  --query "RouteTable.RouteTableId" `
  --output text

aws ec2 create-route `
  --region $REGION `
  --route-table-id $RT_PUBLIC `
  --destination-cidr-block 0.0.0.0/0 `
  --gateway-id $IGW_ID

aws ec2 associate-route-table `
  --region $REGION `
  --route-table-id $RT_PUBLIC `
  --subnet-id $SUB1_ID

Write-Host "Public route table created: $RT_PUBLIC"

# ---------- 5. NAT GATEWAY ----------
$EIP_ALLOC_ID = aws ec2 allocate-address `
  --region $REGION `
  --domain vpc `
  --query "AllocationId" `
  --output text

Write-Host "Elastic IP allocated for NAT: $EIP_ALLOC_ID"

$NAT_GW_ID = aws ec2 create-nat-gateway `
  --region $REGION `
  --subnet-id $SUB1_ID `
  --allocation-id $EIP_ALLOC_ID `
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=alma-nat-gw}]" `
  --query "NatGateway.NatGatewayId" `
  --output text

Write-Host "NAT Gateway creating: $NAT_GW_ID"
Write-Host "Waiting for NAT Gateway to become available..."
aws ec2 wait nat-gateway-available `
  --region $REGION `
  --nat-gateway-ids $NAT_GW_ID

Write-Host "NAT Gateway available: $NAT_GW_ID"

# ---------- 6. PRIVATE ROUTE TABLE ----------
$RT_PRIVATE = aws ec2 create-route-table `
  --region $REGION `
  --vpc-id $VPC_ID `
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=alma-rt-private}]" `
  --query "RouteTable.RouteTableId" `
  --output text

aws ec2 create-route `
  --region $REGION `
  --route-table-id $RT_PRIVATE `
  --destination-cidr-block 0.0.0.0/0 `
  --nat-gateway-id $NAT_GW_ID

aws ec2 associate-route-table `
  --region $REGION `
  --route-table-id $RT_PRIVATE `
  --subnet-id $SUB2_ID

aws ec2 associate-route-table `
  --region $REGION `
  --route-table-id $RT_PRIVATE `
  --subnet-id $SUB3_ID

Write-Host "Private route table created: $RT_PRIVATE"

# ---------- 7. CREATE KEY PAIR ----------
if (Test-Path "$KEY_NAME.pem") {
    Remove-Item "$KEY_NAME.pem" -Force
}

$json = aws ec2 create-key-pair `
  --region $REGION `
  --key-name $KEY_NAME `
  --output json

$keyMaterial = ($json | ConvertFrom-Json).KeyMaterial

[System.IO.File]::WriteAllText(
    (Join-Path $PWD "$KEY_NAME.pem"),
    $keyMaterial,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Key pair created: $KEY_NAME.pem"

icacls "$KEY_NAME.pem" /inheritance:r | Out-Null
icacls "$KEY_NAME.pem" /grant:r "$($env:USERNAME):(R)" | Out-Null

ssh-keygen -y -f ".\$KEY_NAME.pem" | Out-Null
Write-Host "PEM validation passed."

# ---------- 8. CREATE SECURITY GROUPS ----------
$WEB_SG = aws ec2 create-security-group `
  --region $REGION `
  --group-name alma-web-sg `
  --description "Web server SG" `
  --vpc-id $VPC_ID `
  --query "GroupId" `
  --output text

$DB_SG = aws ec2 create-security-group `
  --region $REGION `
  --group-name alma-db-sg `
  --description "Database server SG" `
  --vpc-id $VPC_ID `
  --query "GroupId" `
  --output text

Write-Host "Web SG: $WEB_SG"
Write-Host "DB  SG: $DB_SG"

# WEB SG RULES
aws ec2 authorize-security-group-ingress `
  --region $REGION `
  --group-id $WEB_SG `
  --protocol tcp `
  --port 22 `
  --cidr $MY_IP

aws ec2 authorize-security-group-ingress `
  --region $REGION `
  --group-id $WEB_SG `
  --protocol tcp `
  --port 80 `
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress `
  --region $REGION `
  --group-id $WEB_SG `
  --protocol tcp `
  --port 443 `
  --cidr 0.0.0.0/0

# optional: allow SSH between web instances in same SG
aws ec2 authorize-security-group-ingress `
  --region $REGION `
  --group-id $WEB_SG `
  --protocol tcp `
  --port 22 `
  --source-group $WEB_SG

# DB SG RULES
aws ec2 authorize-security-group-ingress `
  --region $REGION `
  --group-id $DB_SG `
  --protocol tcp `
  --port 22 `
  --cidr $MY_IP

aws ec2 authorize-security-group-ingress `
  --region $REGION `
  --group-id $DB_SG `
  --protocol tcp `
  --port 22 `
  --source-group $WEB_SG

aws ec2 authorize-security-group-ingress `
  --region $REGION `
  --group-id $DB_SG `
  --protocol tcp `
  --port 3306 `
  --source-group $WEB_SG

# ---------- 9. LAUNCH EC2-1 WEB ----------
$WEB_INSTANCE = aws ec2 run-instances `
  --region $REGION `
  --image-id $AMI_ID `
  --instance-type $INSTANCE_TYPE `
  --key-name $KEY_NAME `
  --subnet-id $SUB1_ID `
  --security-group-ids $WEB_SG `
  --associate-public-ip-address `
  --count 1 `
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=alma-ec2-web}]" `
  --user-data "#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y apache2 php libapache2-mod-php php-mysql default-mysql-client
systemctl enable apache2
systemctl start apache2" `
  --query "Instances[0].InstanceId" `
  --output text

Write-Host "Web instance created: $WEB_INSTANCE"

# ---------- 10. LAUNCH EC2-2 DB ----------
$DB1_INSTANCE = aws ec2 run-instances `
  --region $REGION `
  --image-id $AMI_ID `
  --instance-type $INSTANCE_TYPE `
  --key-name $KEY_NAME `
  --subnet-id $SUB2_ID `
  --security-group-ids $DB_SG `
  --count 1 `
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=alma-ec2-db1}]" `
  --user-data "#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb" `
  --query "Instances[0].InstanceId" `
  --output text

Write-Host "DB1 instance created: $DB1_INSTANCE"

# ---------- 11. LAUNCH EC2-3 DB ----------
$DB2_INSTANCE = aws ec2 run-instances `
  --region $REGION `
  --image-id $AMI_ID `
  --instance-type $INSTANCE_TYPE `
  --key-name $KEY_NAME `
  --subnet-id $SUB3_ID `
  --security-group-ids $DB_SG `
  --count 1 `
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=alma-ec2-db2}]" `
  --user-data "#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb" `
  --query "Instances[0].InstanceId" `
  --output text

Write-Host "DB2 instance created: $DB2_INSTANCE"

# ---------- 12. SHOW INSTANCE DETAILS ----------
Write-Host ""
Write-Host "=== INSTANCE DETAILS ==="

aws ec2 describe-instances `
  --region $REGION `
  --instance-ids $WEB_INSTANCE $DB1_INSTANCE $DB2_INSTANCE `
  --query "Reservations[*].Instances[*].[Tags[0].Value,InstanceId,PrivateIpAddress,PublicIpAddress,State.Name,SubnetId]" `
  --output table
