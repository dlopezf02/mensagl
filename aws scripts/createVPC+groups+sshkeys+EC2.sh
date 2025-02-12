#!/bin/bash

# The name of the user for lab
printf "%s" "Insert personal name: "
read ALUMNO

KEY_NAME="ssh-mensagl-2025-${ALUMNO}"
AMI_ID="ami-04b4f1a9cf54c11d0"          # Ubuntu 24.04 AMI ID

# Variables for RDS
RDS_INSTANCE_ID="wordpress-db"
printf "%s" "RDS Wordpress Username: "
read DB_USERNAME
printf "%s" "RDS Wordpress Password: "
read DB_PASSWORD

###########################################################################################################
###########################                      V P C                          ###########################
###########################################################################################################

# VPC_Variables
VPC_NAME="vpc-mensagl-2025-${ALUMNO}"
REGION="us-east-1"
AVAILABILITY_ZONE1="${REGION}a"
AVAILABILITY_ZONE2="${REGION}b"
DESCRIPTION="Mensagl Security group"
MY_IP="0.0.0.0/0" # Replace with your public IP range or '0.0.0.0/0' for open access


# Create VPC and capture its ID
VPC_ID=$(aws ec2 create-vpc --cidr-block "10.0.0.0/16" --instance-tenancy "default" --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}-vpc}]" --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Create public and private subnets, capture their IDs
SUBNET_PUBLIC1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "10.0.1.0/24" --availability-zone $AVAILABILITY_ZONE1 --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-public1-${AVAILABILITY_ZONE1}}]" --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLIC1 --map-public-ip-on-launch
SUBNET_PUBLIC2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "10.0.2.0/24" --availability-zone $AVAILABILITY_ZONE2 --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-public2-${AVAILABILITY_ZONE2}}]" --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUBLIC2 --map-public-ip-on-launch
SUBNET_PRIVATE1=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "10.0.3.0/24" --availability-zone $AVAILABILITY_ZONE1 --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-private1-${AVAILABILITY_ZONE1}}]" --query 'Subnet.SubnetId' --output text)
SUBNET_PRIVATE2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block "10.0.4.0/24" --availability-zone $AVAILABILITY_ZONE2 --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-subnet-private2-${AVAILABILITY_ZONE2}}]" --query 'Subnet.SubnetId' --output text)

# Create Internet Gateway and attach to the VPC
IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# Create public route table and associate public subnets
RTB_PUBLIC=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-rtb-public}]" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PUBLIC --destination-cidr-block "0.0.0.0/0" --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $RTB_PUBLIC --subnet-id $SUBNET_PUBLIC1
aws ec2 associate-route-table --route-table-id $RTB_PUBLIC --subnet-id $SUBNET_PUBLIC2

# Create Elastic IP and NAT Gateway
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${VPC_NAME}-eip-${AVAILABILITY_ZONE1}}]" --query 'AllocationId' --output text)
NATGW_ID=$(aws ec2 create-nat-gateway --subnet-id $SUBNET_PUBLIC1 --allocation-id $EIP_ALLOC_ID --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${VPC_NAME}-nat-public1-${AVAILABILITY_ZONE1}}]" --query 'NatGateway.NatGatewayId' --output text)

# Wait for the NAT Gateway to become available
aws ec2 wait nat-gateway-available --nat-gateway-ids $NATGW_ID

# Create private route tables and associate private subnets
RTB_PRIVATE1=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-rtb-private1-${AVAILABILITY_ZONE1}}]" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PRIVATE1 --destination-cidr-block "0.0.0.0/0" --nat-gateway-id $NATGW_ID
aws ec2 associate-route-table --route-table-id $RTB_PRIVATE1 --subnet-id $SUBNET_PRIVATE1
RTB_PRIVATE2=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-rtb-private2-${AVAILABILITY_ZONE2}}]" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PRIVATE2 --destination-cidr-block "0.0.0.0/0" --nat-gateway-id $NATGW_ID
aws ec2 associate-route-table --route-table-id $RTB_PRIVATE2 --subnet-id $SUBNET_PRIVATE2

# Final verifications
#aws ec2 describe-vpcs --vpc-ids $VPC_ID
#aws ec2 describe-nat-gateways --nat-gateway-ids $NATGW_ID
#aws ec2 describe-route-tables --route-table-ids $RTB_PRIVATE1 $RTB_PRIVATE2

echo "VPC Created !";


###########################################################################################################
########################                    SECURITY GROUPS                        ########################
###########################################################################################################


# Create security group PROXYS
SG_ID_PROXY=$(aws ec2 create-security-group \
  --group-name "Proxy-inverso" \
  --description "$DESCRIPTION" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Proxy-inverso"}]" \
  --query 'GroupId' \
  --output text)
# Add inbound rule to allow SSH
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_PROXY \
  --protocol tcp \
  --port 22 \
  --cidr $MY_IP
# Add inbound rule to allow HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_PROXY \
  --protocol tcp \
  --port 80 \
  --cidr $MY_IP
# Add inbound rule to allow HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_PROXY \
  --protocol tcp \
  --port 443 \
  --cidr $MY_IP



# Create security group XMPP
SG_ID_XMPP=$(aws ec2 create-security-group \
  --group-name "Servidor-Mensajeria" \
  --description "$DESCRIPTION" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Servidor-Mensajeria"}]" \
  --query 'GroupId' \
  --output text)
# Add inbound rule to allow 10000
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 1000 \
  --cidr $MY_IP
# Add inbound rule to allow 5269
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 5269 \
  --cidr $MY_IP
# Add inbound rule to allow 4443
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 4443 \
  --cidr $MY_IP
# Add inbound rule to allow 5281
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 5281 \
  --cidr $MY_IP
# Add inbound rule to allow 5280
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 5280 \
  --cidr $MY_IP
# Add inbound rule to allow 5347
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 5347 \
  --cidr $MY_IP
# Add inbound rule to allow 5222
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 5222 \
  --cidr $MY_IP
# Add inbound rule to allow HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 80 \
  --cidr $MY_IP
# Add inbound rule to allow HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 443 \
  --cidr $MY_IP
# Add inbound rule to allow SSH
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 1000 \
  --cidr $MY_IP
# Add inbound rule to allow 12345
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 12345 \
  --cidr $MY_IP
# Add inbound rule to allow MYSQL
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_XMPP \
  --protocol tcp \
  --port 3306 \
  --cidr $MY_IP








# Create security group MYSQL
SG_ID_MYSQL=$(aws ec2 create-security-group \
  --group-name "Servidor-SGBD" \
  --description "$DESCRIPTION" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Servidor-SGBD"}]" \
  --query 'GroupId' \
  --output text)
# Add inbound rule to allow SSH
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_MYSQL \
  --protocol tcp \
  --port 22 \
  --cidr $MY_IP
# Add inbound rule to allow MYSQL
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_MYSQL \
  --protocol tcp \
  --port 3306 \
  --cidr $MY_IP







# Create security group WORDPRESS
SG_ID_WORDPRESS=$(aws ec2 create-security-group \
  --group-name "Servidor-ticketing" \
  --description "$DESCRIPTION" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="Servidor-ticketing"}]" \
  --query 'GroupId' \
  --output text)
# Add inbound rule to allow SSH
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_WORDPRESS \
  --protocol tcp \
  --port 22 \
  --cidr $MY_IP
# Add inbound rule to allow HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_WORDPRESS \
  --protocol tcp \
  --port 80 \
  --cidr $MY_IP
# Add inbound rule to allow HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID_WORDPRESS \
  --protocol tcp \
  --port 443 \
  --cidr $MY_IP


echo "Sec Groups Created !";

###########################################################################################################
#########################                      KEYS SSH                          ##########################
###########################################################################################################

# Key pair SSH
aws ec2 create-key-pair \
  --key-name "${KEY_NAME}" \
  --query "KeyMaterial" \
  --output text > ${KEY_NAME}.pem

echo "SSH KEYS !";

###########################################################################################################
###########################                      E C 2                          ###########################
###########################################################################################################


####### PROXY

# PROXY-1
# ====== Variables ======
INSTANCE_NAME="PROXY-1"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PUBLIC1}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_PROXY}"  # Security Group ID
PRIVATE_IP="10.0.1.10"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created";







# PROXY-2
# ====== Variables ======
INSTANCE_NAME="PROXY-2"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PUBLIC2}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_PROXY}"  # Security Group ID
PRIVATE_IP="10.0.2.10"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created";





####### MySQL

# MYSQL-1
# ====== Variables ======
INSTANCE_NAME="MYSQ-1"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PRIVATE1}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_MYSQL}"  # Security Group ID
PRIVATE_IP="10.0.3.10"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)


# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created";



####### MySQL

# MYSQL-2
# ====== Variables ======
INSTANCE_NAME="MYSQ-1"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PRIVATE1}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_MYSQL}"  # Security Group ID
PRIVATE_IP="10.0.3.20"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created";



########################################################################
######################### ADD RDS MYSQL INSTANCE #######################
########################################################################

# Create RDS Subnet Group (Requires at Least 2 AZs)
aws rds create-db-subnet-group \
    --db-subnet-group-name wp-rds-subnet-group \
    --db-subnet-group-description "RDS Subnet Group for WordPress" \
    --subnet-ids "$SUBNET_PRIVATE1" "$SUBNET_PRIVATE2"

# Create Security Group for RDS
SG_ID_RDS=$(aws ec2 create-security-group \
  --group-name "RDS-MySQL" \
  --description "Security group for RDS MySQL" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

# Allow MySQL access (replace with actual security group or IP CIDR)
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID_RDS" \
  --protocol tcp \
  --port 3306 \
  --cidr 0.0.0.0/0  # Replace with actual WordPress server CIDR

# Create RDS Instance (Single-AZ in Private Subnet 2)
aws rds create-db-instance \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --db-instance-class db.t3.medium \
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

# Wait for RDS to be available
echo "Waiting for RDS to become available (may take ~10 minutes)..."
aws rds wait db-instance-available --db-instance-identifier "$RDS_INSTANCE_ID"

# Retrieve RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)
echo "RDS Endpoint: $RDS_ENDPOINT"











####### XMPP

# XMPP-1
# ====== Variables ======
INSTANCE_NAME="XMPP-1"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PRIVATE1}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_XMPP}"  # Security Group ID
PRIVATE_IP="10.0.3.100"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)


# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created";




# XMPP-2
# ====== Variables ======
INSTANCE_NAME="XMPP-2"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PRIVATE1}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_XMPP}"  # Security Group ID
PRIVATE_IP="10.0.3.200"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)


# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created";







####### WORDPRESS

# WORDPRESS-1
# ====== Variables ======
INSTANCE_NAME="WORDPRESS-1"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PRIVATE2}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_WORDPRESS}"  # Security Group ID
PRIVATE_IP="10.0.4.100"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created";




# WORDPRESS-2
# ====== Variables ======
INSTANCE_NAME="WORDPRESS-1"                 # Tag: Name of the EC2 instance
SUBNET_ID="${SUBNET_PRIVATE2}"           # Subnet ID
SECURITY_GROUP_ID="${SG_ID_WORDPRESS}"  # Security Group ID
PRIVATE_IP="10.0.4.200"                # Private IP for the instance

INSTANCE_TYPE="t2.micro"                # EC2 Instance Type
KEY_NAME="${KEY_NAME}"                  # Name of the SSH Key Pair
VOLUME_SIZE=8                           # Size of the root EBS volume (in GB)

# ====== Create EC2 Instance ======
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} created";
