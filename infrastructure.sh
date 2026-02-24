#!/bin/bash
# ==============================================
# Three-Tier VPC Architecture — AWS CLI Script
# Author: Ayotomiwa Ayorinde
#
# What this script builds:
# - Custom VPC with public and private subnets
# - Internet Gateway for public internet access
# - NAT Gateway for private subnet outbound access
# - Route Tables for traffic direction
# - Security Groups for instance level firewall
# - NACLs for subnet level firewall
# - Bastion Host EC2 in public subnet
# - Web Server EC2 in public subnet
# - App Server EC2 in private subnet
# - IAM roles attached to EC2 instances
# ==============================================

set -e  # Exit immediately if any command fails

# Colours for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Three-Tier VPC Deployment Starting...${NC}"
echo -e "${GREEN}============================================${NC}"

# ==============================================
# VARIABLES — edit these if needed
# ==============================================
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"
AZ="us-east-1a"
MY_IP=$(curl -s https://checkip.amazonaws.com)/32

echo -e "${YELLOW}Configuration:${NC}"
echo "  Region:              $REGION"
echo "  VPC CIDR:            $VPC_CIDR"
echo "  Public Subnet CIDR:  $PUBLIC_SUBNET_CIDR"
echo "  Private Subnet CIDR: $PRIVATE_SUBNET_CIDR"
echo "  Availability Zone:   $AZ"
echo "  Your IP:             $MY_IP"
echo -e "${GREEN}============================================${NC}"



# ==============================================
# SECTION 1: CREATE VPC
# ==============================================
echo -e "${YELLOW}Creating VPC...${NC}"

# Create the VPC and capture its ID
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --region $REGION \
  --query "Vpc.VpcId" \
  --output text)

echo "  VPC created: $VPC_ID"

# Name the VPC using a tag
aws ec2 create-tags \
  --resources $VPC_ID \
  --tags Key=Name,Value=three-tier-vpc \
  --region $REGION

# Enable DNS hostnames so EC2 instances get
# human readable hostnames not just IP addresses
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames \
  --region $REGION

# Enable DNS resolution so instances can
# resolve public DNS names from within the VPC
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-support \
  --region $REGION

echo -e "${GREEN}  ✓ VPC ready: $VPC_ID${NC}"


# ==============================================
# SECTION 2: CREATE SUBNETS
# ==============================================
echo -e "${YELLOW}Creating Subnets...${NC}"

# Create the public subnet
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PUBLIC_SUBNET_CIDR \
  --availability-zone $AZ \
  --region $REGION \
  --query "Subnet.SubnetId" \
  --output text)

echo "  Public subnet created: $PUBLIC_SUBNET_ID"

# Name the public subnet
aws ec2 create-tags \
  --resources $PUBLIC_SUBNET_ID \
  --tags Key=Name,Value=three-tier-public-subnet \
  --region $REGION

# Enable auto-assign public IP on public subnet
# Any EC2 launched here automatically gets a public IP
aws ec2 modify-subnet-attribute \
  --subnet-id $PUBLIC_SUBNET_ID \
  --map-public-ip-on-launch \
  --region $REGION

echo -e "${GREEN}  ✓ Public subnet ready: $PUBLIC_SUBNET_ID${NC}"

# Create the private subnet
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SUBNET_CIDR \
  --availability-zone $AZ \
  --region $REGION \
  --query "Subnet.SubnetId" \
  --output text)

echo "  Private subnet created: $PRIVATE_SUBNET_ID"

# Name the private subnet
aws ec2 create-tags \
  --resources $PRIVATE_SUBNET_ID \
  --tags Key=Name,Value=three-tier-private-subnet \
  --region $REGION

# Private subnet deliberately has NO auto-assign public IP
# Private instances should never have public IP addresses

echo -e "${GREEN}  ✓ Private subnet ready: $PRIVATE_SUBNET_ID${NC}"




# ==============================================
# SECTION 3: CREATE INTERNET GATEWAY
# ==============================================
echo -e "${YELLOW}Creating Internet Gateway...${NC}"

# Create the Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query "InternetGateway.InternetGatewayId" \
  --output text)

echo "  Internet Gateway created: $IGW_ID"

# Name the Internet Gateway
aws ec2 create-tags \
  --resources $IGW_ID \
  --tags Key=Name,Value=three-tier-igw \
  --region $REGION

# Attach the Internet Gateway to the VPC
# Without this step the IGW exists but does nothing
aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID \
  --region $REGION

echo -e "${GREEN}  ✓ Internet Gateway created and attached: $IGW_ID${NC}"



# ==============================================
# SECTION 4: CREATE NAT GATEWAY
# ==============================================
echo -e "${YELLOW}Creating NAT Gateway...${NC}"

# Step 1: Allocate an Elastic IP address
# NAT Gateway needs a fixed public IP address
ELASTIC_IP_ALLOC_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --region $REGION \
  --query "AllocationId" \
  --output text)

echo "  Elastic IP allocated: $ELASTIC_IP_ALLOC_ID"

# Name the Elastic IP
aws ec2 create-tags \
  --resources $ELASTIC_IP_ALLOC_ID \
  --tags Key=Name,Value=three-tier-nat-eip \
  --region $REGION

# Step 2: Create the NAT Gateway in the PUBLIC subnet
# IMPORTANT: NAT Gateway always goes in PUBLIC subnet
# It needs access to the Internet Gateway to work
NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET_ID \
  --allocation-id $ELASTIC_IP_ALLOC_ID \
  --region $REGION \
  --query "NatGateway.NatGatewayId" \
  --output text)

echo "  NAT Gateway created: $NAT_GW_ID"

# Name the NAT Gateway
aws ec2 create-tags \
  --resources $NAT_GW_ID \
  --tags Key=Name,Value=three-tier-nat-gw \
  --region $REGION

# Step 3: Wait for NAT Gateway to become available
# This takes 1-2 minutes — script pauses here automatically
echo -e "${YELLOW}  Waiting for NAT Gateway to become available...${NC}"
echo "  This takes about 60-90 seconds. Please wait..."

aws ec2 wait nat-gateway-available \
  --nat-gateway-ids $NAT_GW_ID \
  --region $REGION

echo -e "${GREEN}  ✓ NAT Gateway ready: $NAT_GW_ID${NC}"