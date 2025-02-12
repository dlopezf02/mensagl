#!/bin/bash

# sudo prosodyctl --root cert import /etc/certs/

# The name of the user for lab
printf "%s" "Insert personal name: "
read ALUMNO
# The mail for certs and wordpress config
printf "%s" "Insert email: "
read EMAIL

# DuckDNS variables
printf "%s" "DuckDNS token: "
read DUCKDNS_TOKEN
printf "%s" "DuckDNS domain-xmpp: "
read DUCKDNS_SUBDOMAIN
printf "%s" "DuckDNS domain-wp: "
read DUCKDNS_SUBDOMAIN2

echo "Starting script"

# Key pair SSH
KEY_NAME="ssh-mensagl-2025-${ALUMNO}"
AMI_ID="ami-04b4f1a9cf54c11d0"          # Ubuntu 24.04 AMI ID

# Variables for RDS
RDS_INSTANCE_ID="wordpress-db"
printf "%s" "RDS Wordpress Database: "
read wDBName
printf "%s" "RDS & MySQL XMPP Username: "
read DB_USERNAME
printf "%s" "RDS & MySQL XMPP Password: "
read DB_PASSWORD


###########################################################################################################
###########################                      V P C                          ###########################
###########################################################################################################
export EDITOR=true

# VPC Variables
VPC_NAME="vpc-mensagl-2025-${ALUMNO}"
REGION="us-east-1"
AVAILABILITY_ZONE1="${REGION}a"
AVAILABILITY_ZONE2="${REGION}b"
DESCRIPTION="Mensagl Security groups"
MY_IP="0.0.0.0/0"

# Create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block "10.0.0.0/16" --instance-tenancy "default" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}-vpc}]" \
  --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Public Subnet 1
SUBNET_PUBLIC1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "10.0.1.0/24" \
  --availability-zone $AVAILABILITY_ZONE1 \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-public1-${AVAILABILITY_ZONE1}}]" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLIC1 --map-public-ip-on-launch

# Public Subnet 2
SUBNET_PUBLIC2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "10.0.2.0/24" \
  --availability-zone $AVAILABILITY_ZONE2 \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-public2-${AVAILABILITY_ZONE2}}]" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLIC2 --map-public-ip-on-launch

# Private Subnet 1
SUBNET_PRIVATE1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "10.0.3.0/24" \
  --availability-zone $AVAILABILITY_ZONE1 \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE1}}]" \
  --query 'Subnet.SubnetId' --output text)

# Private Subnet 2
SUBNET_PRIVATE2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "10.0.4.0/24" \
  --availability-zone $AVAILABILITY_ZONE2 \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-private2-${AVAILABILITY_ZONE2}}]" \
  --query 'Subnet.SubnetId' --output text)




# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Create public route table
RTB_PUBLIC=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-rtb-public}]" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PUBLIC --destination-cidr-block "0.0.0.0/0" --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $RTB_PUBLIC --subnet-id $SUBNET_PUBLIC1
aws ec2 associate-route-table --route-table-id $RTB_PUBLIC --subnet-id $SUBNET_PUBLIC2

# Create Elastic IP and NAT Gateway
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NATGW_ID=$(aws ec2 create-nat-gateway --subnet-id $SUBNET_PUBLIC1 --allocation-id $EIP_ALLOC_ID \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${VPC_NAME}-nat-public1-${AVAILABILITY_ZONE1}}]" \
  --query 'NatGateway.NatGatewayId' --output text)

# Wait for NAT Gateway
aws ec2 wait nat-gateway-available --nat-gateway-ids $NATGW_ID

# Create private route table and associate both private subnets
RTB_PRIVATE=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-rtb-private}]" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PRIVATE --destination-cidr-block "0.0.0.0/0" --nat-gateway-id $NATGW_ID
aws ec2 associate-route-table --route-table-id $RTB_PRIVATE --subnet-id $SUBNET_PRIVATE1
aws ec2 associate-route-table --route-table-id $RTB_PRIVATE --subnet-id $SUBNET_PRIVATE2

echo "VPC Created !"




###########################################################################################################
########################                    SECURITY GROUPS                        ########################
###########################################################################################################

# Security group PROXYS
SG_ID_PROXY=$(aws ec2 create-security-group \
  --group-name "Proxy-inverso" \
  --description "$DESCRIPTION" --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Proxy-inverso"}]" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 22 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 80 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 443 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol udp --port 10000 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 5269 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 4443 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 5281 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 5280 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 5347 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 5222 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 12345 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_PROXY --protocol tcp --port 3306 --cidr $MY_IP





# Security group XMPP
SG_ID_XMPP=$(aws ec2 create-security-group \
  --group-name "Servidor-Mensajeria" \
  --description "$DESCRIPTION" --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Servidor-Mensajeria"}]" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 1000 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 5269 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 5270 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 4443 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 5281 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 5280 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 5347 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 5222 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 80 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 443 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 22 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 12345 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol tcp --port 3306 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_XMPP --protocol -1 --source-group $SG_ID_PROXY





# Security group MYSQL
SG_ID_MYSQL=$(aws ec2 create-security-group \
  --group-name "Servidor-SGBD" \
  --description "$DESCRIPTION" --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Servidor-SGBD"}]" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_ID_MYSQL --protocol tcp --port 22 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_MYSQL --protocol tcp --port 3306 --cidr $MY_IP







# Security group WORDPRESS
SG_ID_WORDPRESS=$(aws ec2 create-security-group \
  --group-name "Servidor-ticketing" \
  --description "$DESCRIPTION" --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Servidor-ticketing"}]" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_ID_WORDPRESS --protocol tcp --port 22 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_WORDPRESS --protocol tcp --port 80 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_WORDPRESS --protocol tcp --port 443 --cidr $MY_IP
aws ec2 authorize-security-group-ingress --group-id $SG_ID_WORDPRESS --protocol -1 --source-group $SG_ID_PROXY


echo "Sec Groups Created !";



###########################################################################################################
#########################                      KEYS SSH                          ##########################
###########################################################################################################

aws ec2 create-key-pair \
  --key-name "${KEY_NAME}" \
  --query "KeyMaterial" \
  --output text > ${KEY_NAME}.pem

aws ec2 create-key-pair \
  --key-name "${KEY_NAME}-RAID" \
  --query "KeyMaterial" \
  --output text > ${KEY_NAME}-RAID.pem

echo "SSH KEYS !";







#aws rds delete-db-instance \
#    --db-instance-identifier "wordpress-db" \
#    --skip-final-snapshot \
#    --region "us-east-1"
#aws rds describe-db-instances --db-instance-identifier "wordpress-db"
#aws rds delete-db-subnet-group --db-subnet-group-name wp-rds-subnet-group
#aws rds describe-db-subnet-groups --db-subnet-group-name wp-rds-subnet-group




########################################################################
#######################     RDS MYSQL INSTANCE     #####################
########################################################################

# RDS Subnet Group
aws rds create-db-subnet-group \
    --db-subnet-group-name wp-rds-subnet-group \
    --db-subnet-group-description "RDS Subnet Group for WordPress" \
    --subnet-ids "$SUBNET_PRIVATE1" "$SUBNET_PRIVATE2"

# Security Group RDS
SG_ID_RDS=$(aws ec2 create-security-group \
  --group-name "RDS-MySQL" \
  --description "Security group for RDS MySQL" \
  --vpc-id "$VPC_ID" --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id "$SG_ID_RDS" --protocol tcp --port 3306 --cidr 0.0.0.0/0

# RDS Instance
aws rds create-db-instance \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --db-instance-class db.t3.micro \
    --engine mysql \
    --allocated-storage 20 \
    --storage-type gp2 \
    --master-username "$DB_USERNAME" \
    --master-user-password "$DB_PASSWORD" \
    --db-subnet-group-name wp-rds-subnet-group \
    --vpc-security-group-ids "$SG_ID_RDS" \
    --backup-retention-period 7 \
    --no-publicly-accessible \
    --region "$REGION" \
    --availability-zone "$AVAILABILITY_ZONE1" \
    --no-multi-az  # Ensures Single-AZ deployment

# Wait RDS
echo "Waiting for RDS (~10 minutes)..."
aws rds wait db-instance-available --db-instance-identifier "$RDS_INSTANCE_ID"

# RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE_ID" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
echo "RDS Endpoint: $RDS_ENDPOINT"





###########################################################################################################
###########################                      E C 2                          ###########################
###########################################################################################################


SRC_DIR="./user-data/vms"
DEST_DIR="./user-data/result"

mkdir -p "$DEST_DIR";
cp -r "$SRC_DIR/"* "$DEST_DIR/";

find "$DEST_DIR" -type f -name "*.sh" -exec sed -i \
    -e "s|\${DUCKDNS_TOKEN}|${DUCKDNS_TOKEN}|g" \
    -e "s|\${DUCKDNS_SUBDOMAIN}|${DUCKDNS_SUBDOMAIN}|g" \
    -e "s|\${DUCKDNS_SUBDOMAIN2}|${DUCKDNS_SUBDOMAIN2}|g" \
    -e "s|\${ALUMNO}|${ALUMNO}|g" \
    -e "s|\${EMAIL}|${EMAIL}|g" \
    -e "s|\${RDS_INSTANCE_ID}|${RDS_INSTANCE_ID}|g" \
    -e "s|\${RDS_ENDPOINT}|${RDS_ENDPOINT}|g" \
    -e "s|\${wDBName}|${wDBName}|g" \
    -e "s|\${DB_USERNAME}|${DB_USERNAME}|g" \
    -e "s|\${DB_PASSWORD}|${DB_PASSWORD}|g" {} +

chmod +x "$DEST_DIR"/*.sh;
echo "SCRIPTS MODIFIED";





####### PROXY

# PROXY-1
# ====== Variables ======
INSTANCE_NAME="PROXY-1"
SUBNET_ID="${SUBNET_PUBLIC1}"
SECURITY_GROUP_ID="${SG_ID_PROXY}"
PRIVATE_IP="10.0.1.10"

INSTANCE_TYPE="t2.micro"
KEY_NAME="${KEY_NAME}"
VOLUME_SIZE=8

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data file://$DEST_DIR/nginx.sh \
    --query "Instances[0].InstanceId" \
    --output text)

echo "${INSTANCE_NAME} created"





# PROXY-2
# ====== Variables ======
INSTANCE_NAME="PROXY-2"
SUBNET_ID="${SUBNET_PUBLIC2}"
SECURITY_GROUP_ID="${SG_ID_PROXY}"
PRIVATE_IP="10.0.2.10"

INSTANCE_TYPE="t2.micro"
KEY_NAME="${KEY_NAME}"
VOLUME_SIZE=8

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data file://$DEST_DIR/nginx2.sh \
    --query "Instances[0].InstanceId" \
    --output text)

echo "${INSTANCE_NAME} created"





####### MySQL

# MYSQL-1
# ====== Variables ======
INSTANCE_NAME="MYSQL-1"
SUBNET_ID="${SUBNET_PRIVATE1}"
SECURITY_GROUP_ID="${SG_ID_MYSQL}"
PRIVATE_IP="10.0.3.10"

INSTANCE_TYPE="t2.micro"
KEY_NAME="${KEY_NAME}"
VOLUME_SIZE=8

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data file://$DEST_DIR/mysql.sh \
    --query "Instances[0].InstanceId" \
    --output text)

echo "${INSTANCE_NAME} created"




# MYSQL-2
# ====== Variables ======
INSTANCE_NAME="MYSQL-2"
SUBNET_ID="${SUBNET_PRIVATE1}"
SECURITY_GROUP_ID="${SG_ID_MYSQL}"
PRIVATE_IP="10.0.3.20"

INSTANCE_TYPE="t2.micro"
KEY_NAME="${KEY_NAME}"
VOLUME_SIZE=8

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data file://$DEST_DIR/mysql2.sh \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created"





####### XMPP

# XMPP-1
# ====== Variables ======
INSTANCE_NAME="XMPP-1"
SUBNET_ID="${SUBNET_PRIVATE1}"
SECURITY_GROUP_ID="${SG_ID_XMPP}"
PRIVATE_IP="10.0.3.100"

INSTANCE_TYPE="t2.micro"
KEY_NAME="${KEY_NAME}"
VOLUME_SIZE=8

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --user-data file://$DEST_DIR/xmpp.sh \
    --output text)
echo "${INSTANCE_NAME} created";



# XMPP-2
# ====== Variables ======
INSTANCE_NAME="XMPP-2"
SUBNET_ID="${SUBNET_PRIVATE1}"
SECURITY_GROUP_ID="${SG_ID_XMPP}"
PRIVATE_IP="10.0.3.200"

INSTANCE_TYPE="t2.micro"
KEY_NAME="${KEY_NAME}"
VOLUME_SIZE=8

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --user-data file://$DEST_DIR/xmpp.sh \
    --output text)
echo "${INSTANCE_NAME} created";







####### WORDPRESS

# WORDPRESS-1
# ====== Variables ======
INSTANCE_NAME="WORDPRESS-1"
SUBNET_ID="${SUBNET_PRIVATE2}"
SECURITY_GROUP_ID="${SG_ID_WORDPRESS}"
PRIVATE_IP="10.0.4.100"

INSTANCE_TYPE="t2.micro"
KEY_NAME="${KEY_NAME}"
VOLUME_SIZE=8

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data file://$DEST_DIR/wordpress.sh \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created"




# WORDPRESS-2
# ====== Variables ======
INSTANCE_NAME="WORDPRESS-2"
SUBNET_ID="${SUBNET_PRIVATE2}"
SECURITY_GROUP_ID="${SG_ID_WORDPRESS}"
PRIVATE_IP="10.0.4.200"

INSTANCE_TYPE="t2.micro"
KEY_NAME="${KEY_NAME}"
VOLUME_SIZE=8

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data file://$DEST_DIR/wordpress.sh \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created"

































# ====== Create Security Group ======
SG_ID_UBUNTU=$(aws ec2 create-security-group \
    --group-name "RAID-RSYNC" \
    --description "Security Group for Ubuntu VM with RAID1" \
    --vpc-id "$VPC_ID" \
    --query "GroupId" \
    --output text)
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID_UBUNTU" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Allow HTTP (Port 80) - If you plan to run a web server
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID_UBUNTU" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

# Allow HTTPS (Port 443) - If needed
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID_UBUNTU" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0
# Allow SSH
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID_UBUNTU" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Allow all outbound traffic
aws ec2 authorize-security-group-egress \
    --group-id "$SG_ID_UBUNTU" \
    --protocol -1 \
    --port all \
    --cidr 0.0.0.0/0


# ====== Variables ======
INSTANCE_NAME="RAID-RSYNC"                    
SUBNET_ID="${SUBNET_PRIVATE1}"               
SECURITY_GROUP_ID="${SG_ID_UBUNTU}"          
PRIVATE_IP="10.0.3.250"                      

INSTANCE_TYPE="t2.micro"              

ROOT_VOLUME_SIZE=8                           
RAID_VOLUME_SIZE=20                           
VOLUME_TYPE="gp2"                            

# ====== Create Two EBS Volumes for RAID 1 ======
VOLUME_ID_1=$(aws ec2 create-volume \
    --size $RAID_VOLUME_SIZE \
    --volume-type $VOLUME_TYPE \
    --availability-zone $AVAILABILITY_ZONE1 \
    --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${INSTANCE_NAME}-RAID1-DISK1}]" \
    --query "VolumeId" \
    --output text)

VOLUME_ID_2=$(aws ec2 create-volume \
    --size $RAID_VOLUME_SIZE \
    --volume-type $VOLUME_TYPE \
    --availability-zone $AVAILABILITY_ZONE1 \
    --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${INSTANCE_NAME}-RAID1-DISK2}]" \
    --query "VolumeId" \
    --output text)

echo "Created EBS Volumes: ${VOLUME_ID_1}, ${VOLUME_ID_2}"


# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "${KEY_NAME}-RAID" \
    --block-device-mappings "[
        {\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$ROOT_VOLUME_SIZE,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}
    ]" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data file://$DEST_DIR/raid_rsync.sh \
    --query "Instances[0].InstanceId" \
    --output text)

echo "EC2 Instance Created: ${INSTANCE_ID}"


# ====== Attach the Volumes ======
aws ec2 attach-volume --volume-id $VOLUME_ID_1 --instance-id $INSTANCE_ID --device /dev/xvdf
aws ec2 attach-volume --volume-id $VOLUME_ID_2 --instance-id $INSTANCE_ID --device /dev/xvdg

echo "Volumes attached to ${INSTANCE_ID}: $VOLUME_ID_1 (/dev/xvdf), $VOLUME_ID_2 (/dev/xvdg)"
