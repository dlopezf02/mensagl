#!/bin/bash

########################################################################
######################### ADD RDS MYSQL INSTANCE #######################
########################################################################

# Variables

RDS_INSTANCE_ID="wordpress-db"
printf "%s" "RDS Wordpress Username: "
read DB_USERNAME
printf "%s" "RDS Wordpress Password: "
read DB_PASSWORD

REGION="us-east-1"
AVAILABILITY_ZONE="${REGION}a"
SUBNET_PRIVATE2="subnet-X"
SUBNET_PRIVATE1="subnet-Y"
VPC_ID="vpc-Z"


# Create RDS Subnet Group
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

# Allow MySQL access
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
    --availability-zone "$AVAILABILITY_ZONE" \
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
