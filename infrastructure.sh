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



# ==============================================
# SECTION 5: CREATE ROUTE TABLES
# ==============================================
echo -e "${YELLOW}Creating Route Tables...${NC}"

# ------------------------------------------
# PUBLIC ROUTE TABLE
# ------------------------------------------
# Create the public route table
PUBLIC_RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "RouteTable.RouteTableId" \
  --output text)

echo "  Public route table created: $PUBLIC_RT_ID"

# Name the public route table
aws ec2 create-tags \
  --resources $PUBLIC_RT_ID \
  --tags Key=Name,Value=three-tier-public-rt \
  --region $REGION

# Add route to Internet Gateway
# This is what makes the subnet PUBLIC
# All internet-bound traffic (0.0.0.0/0) goes through IGW
aws ec2 create-route \
  --route-table-id $PUBLIC_RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $REGION

echo "  Route added: 0.0.0.0/0 → Internet Gateway"

# Associate public route table with public subnet
aws ec2 associate-route-table \
  --route-table-id $PUBLIC_RT_ID \
  --subnet-id $PUBLIC_SUBNET_ID \
  --region $REGION

echo -e "${GREEN}  ✓ Public route table ready: $PUBLIC_RT_ID${NC}"

# ------------------------------------------
# PRIVATE ROUTE TABLE
# ------------------------------------------
# Create the private route table
PRIVATE_RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "RouteTable.RouteTableId" \
  --output text)

echo "  Private route table created: $PRIVATE_RT_ID"

# Name the private route table
aws ec2 create-tags \
  --resources $PRIVATE_RT_ID \
  --tags Key=Name,Value=three-tier-private-rt \
  --region $REGION

# Add route to NAT Gateway
# Private instances can reach internet OUTBOUND only
# Internet cannot reach private instances INBOUND
aws ec2 create-route \
  --route-table-id $PRIVATE_RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id $NAT_GW_ID \
  --region $REGION

echo "  Route added: 0.0.0.0/0 → NAT Gateway"

# Associate private route table with private subnet
aws ec2 associate-route-table \
  --route-table-id $PRIVATE_RT_ID \
  --subnet-id $PRIVATE_SUBNET_ID \
  --region $REGION

echo -e "${GREEN}  ✓ Private route table ready: $PRIVATE_RT_ID${NC}"





# ==============================================
# SECTION 6: CREATE SECURITY GROUPS
# ==============================================
echo -e "${YELLOW}Creating Security Groups...${NC}"

# ------------------------------------------
# SECURITY GROUP 1: BASTION HOST
# ------------------------------------------
BASTION_SG_ID=$(aws ec2 create-security-group \
  --group-name "three-tier-bastion-sg" \
  --description "Security group for bastion host - SSH access from my IP only" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "GroupId" \
  --output text)

echo "  Bastion security group created: $BASTION_SG_ID"

# Name the bastion security group
aws ec2 create-tags \
  --resources $BASTION_SG_ID \
  --tags Key=Name,Value=three-tier-bastion-sg \
  --region $REGION

# Allow SSH from your IP address only
aws ec2 authorize-security-group-ingress \
  --group-id $BASTION_SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr $MY_IP \
  --region $REGION

echo "  Bastion inbound: SSH (22) from $MY_IP only"
echo -e "${GREEN}  ✓ Bastion security group ready: $BASTION_SG_ID${NC}"

# ------------------------------------------
# SECURITY GROUP 2: WEB SERVER
# ------------------------------------------
WEB_SG_ID=$(aws ec2 create-security-group \
  --group-name "three-tier-web-sg" \
  --description "Security group for web server - HTTP HTTPS from internet SSH from bastion" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "GroupId" \
  --output text)

echo "  Web server security group created: $WEB_SG_ID"

# Name the web server security group
aws ec2 create-tags \
  --resources $WEB_SG_ID \
  --tags Key=Name,Value=three-tier-web-sg \
  --region $REGION

# Allow HTTP from anywhere — public website
aws ec2 authorize-security-group-ingress \
  --group-id $WEB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region $REGION

echo "  Web inbound: HTTP (80) from anywhere"

# Allow HTTPS from anywhere — public website
aws ec2 authorize-security-group-ingress \
  --group-id $WEB_SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --region $REGION

echo "  Web inbound: HTTPS (443) from anywhere"

# Allow SSH from bastion security group only
# Notice we reference the security group ID not an IP
aws ec2 authorize-security-group-ingress \
  --group-id $WEB_SG_ID \
  --protocol tcp \
  --port 22 \
  --source-group $BASTION_SG_ID \
  --region $REGION

echo "  Web inbound: SSH (22) from bastion SG only"
echo -e "${GREEN}  ✓ Web server security group ready: $WEB_SG_ID${NC}"

# ------------------------------------------
# SECURITY GROUP 3: APP SERVER
# ------------------------------------------
APP_SG_ID=$(aws ec2 create-security-group \
  --group-name "three-tier-app-sg" \
  --description "Security group for app server - port 8080 from web server SSH from bastion" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "GroupId" \
  --output text)

echo "  App server security group created: $APP_SG_ID"

# Name the app server security group
aws ec2 create-tags \
  --resources $APP_SG_ID \
  --tags Key=Name,Value=three-tier-app-sg \
  --region $REGION

# Allow port 8080 from web server security group only
# App server only accepts traffic from web server
aws ec2 authorize-security-group-ingress \
  --group-id $APP_SG_ID \
  --protocol tcp \
  --port 8080 \
  --source-group $WEB_SG_ID \
  --region $REGION

echo "  App inbound: Port 8080 from web SG only"

# Allow SSH from bastion security group only
aws ec2 authorize-security-group-ingress \
  --group-id $APP_SG_ID \
  --protocol tcp \
  --port 22 \
  --source-group $BASTION_SG_ID \
  --region $REGION

echo "  App inbound: SSH (22) from bastion SG only"
echo -e "${GREEN}  ✓ App server security group ready: $APP_SG_ID${NC}"




# ==============================================
# SECTION 7: CREATE NACLs
# ==============================================
echo -e "${YELLOW}Creating Network ACLs...${NC}"

# ------------------------------------------
# PUBLIC SUBNET NACL
# ------------------------------------------
PUBLIC_NACL_ID=$(aws ec2 create-network-acl \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "NetworkAcl.NetworkAclId" \
  --output text)

echo "  Public NACL created: $PUBLIC_NACL_ID"

# Name the public NACL
aws ec2 create-tags \
  --resources $PUBLIC_NACL_ID \
  --tags Key=Name,Value=three-tier-public-nacl \
  --region $REGION

# INBOUND RULES FOR PUBLIC NACL
# Rule 100: Allow HTTP from anywhere
aws ec2 create-network-acl-entry \
  --network-acl-id $PUBLIC_NACL_ID \
  --rule-number 100 \
  --protocol tcp \
  --rule-action allow \
  --ingress \
  --cidr-block 0.0.0.0/0 \
  --port-range From=80,To=80 \
  --region $REGION

echo "  Public NACL inbound: Rule 100 - Allow HTTP (80)"

# Rule 110: Allow HTTPS from anywhere
aws ec2 create-network-acl-entry \
  --network-acl-id $PUBLIC_NACL_ID \
  --rule-number 110 \
  --protocol tcp \
  --rule-action allow \
  --ingress \
  --cidr-block 0.0.0.0/0 \
  --port-range From=443,To=443 \
  --region $REGION

echo "  Public NACL inbound: Rule 110 - Allow HTTPS (443)"

# Rule 120: Allow SSH from your IP only
aws ec2 create-network-acl-entry \
  --network-acl-id $PUBLIC_NACL_ID \
  --rule-number 120 \
  --protocol tcp \
  --rule-action allow \
  --ingress \
  --cidr-block $MY_IP \
  --port-range From=22,To=22 \
  --region $REGION

echo "  Public NACL inbound: Rule 120 - Allow SSH (22) from $MY_IP"

# Rule 130: Allow ephemeral ports for return traffic
# CRITICAL — NACLs are stateless so return traffic
# must be explicitly allowed on ports 1024-65535
aws ec2 create-network-acl-entry \
  --network-acl-id $PUBLIC_NACL_ID \
  --rule-number 130 \
  --protocol tcp \
  --rule-action allow \
  --ingress \
  --cidr-block 0.0.0.0/0 \
  --port-range From=1024,To=65535 \
  --region $REGION

echo "  Public NACL inbound: Rule 130 - Allow ephemeral ports (1024-65535)"

# OUTBOUND RULES FOR PUBLIC NACL
# Rule 100: Allow HTTP outbound
aws ec2 create-network-acl-entry \
  --network-acl-id $PUBLIC_NACL_ID \
  --rule-number 100 \
  --protocol tcp \
  --rule-action allow \
  --egress \
  --cidr-block 0.0.0.0/0 \
  --port-range From=80,To=80 \
  --region $REGION

echo "  Public NACL outbound: Rule 100 - Allow HTTP (80)"

# Rule 110: Allow HTTPS outbound
aws ec2 create-network-acl-entry \
  --network-acl-id $PUBLIC_NACL_ID \
  --rule-number 110 \
  --protocol tcp \
  --rule-action allow \
  --egress \
  --cidr-block 0.0.0.0/0 \
  --port-range From=443,To=443 \
  --region $REGION

echo "  Public NACL outbound: Rule 110 - Allow HTTPS (443)"

# Rule 120: Allow SSH outbound to VPC
# Needed for bastion to SSH into private instances
aws ec2 create-network-acl-entry \
  --network-acl-id $PUBLIC_NACL_ID \
  --rule-number 120 \
  --protocol tcp \
  --rule-action allow \
  --egress \
  --cidr-block $VPC_CIDR \
  --port-range From=22,To=22 \
  --region $REGION

echo "  Public NACL outbound: Rule 120 - Allow SSH (22) to VPC"

# Rule 130: Allow ephemeral ports outbound
# Needed for responses to go back to clients
aws ec2 create-network-acl-entry \
  --network-acl-id $PUBLIC_NACL_ID \
  --rule-number 130 \
  --protocol tcp \
  --rule-action allow \
  --egress \
  --cidr-block 0.0.0.0/0 \
  --port-range From=1024,To=65535 \
  --region $REGION

echo "  Public NACL outbound: Rule 130 - Allow ephemeral ports (1024-65535)"

# Associate public NACL with public subnet
aws ec2 replace-network-acl-association \
  --association-id $(aws ec2 describe-network-acls \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
    --query "NetworkAcls[0].Associations[?SubnetId=='$PUBLIC_SUBNET_ID'].NetworkAclAssociationId" \
    --output text \
    --region $REGION) \
  --network-acl-id $PUBLIC_NACL_ID \
  --region $REGION

echo -e "${GREEN}  ✓ Public NACL associated with public subnet${NC}"

# ------------------------------------------
# PRIVATE SUBNET NACL
# ------------------------------------------
PRIVATE_NACL_ID=$(aws ec2 create-network-acl \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query "NetworkAcl.NetworkAclId" \
  --output text)

echo "  Private NACL created: $PRIVATE_NACL_ID"

# Name the private NACL
aws ec2 create-tags \
  --resources $PRIVATE_NACL_ID \
  --tags Key=Name,Value=three-tier-private-nacl \
  --region $REGION

# INBOUND RULES FOR PRIVATE NACL
# Rule 100: Allow port 8080 from public subnet only
aws ec2 create-network-acl-entry \
  --network-acl-id $PRIVATE_NACL_ID \
  --rule-number 100 \
  --protocol tcp \
  --rule-action allow \
  --ingress \
  --cidr-block $PUBLIC_SUBNET_CIDR \
  --port-range From=8080,To=8080 \
  --region $REGION

echo "  Private NACL inbound: Rule 100 - Allow port 8080 from public subnet"

# Rule 110: Allow SSH from public subnet
# Bastion is in public subnet so SSH comes from there
aws ec2 create-network-acl-entry \
  --network-acl-id $PRIVATE_NACL_ID \
  --rule-number 110 \
  --protocol tcp \
  --rule-action allow \
  --ingress \
  --cidr-block $PUBLIC_SUBNET_CIDR \
  --port-range From=22,To=22 \
  --region $REGION

echo "  Private NACL inbound: Rule 110 - Allow SSH (22) from public subnet"

# Rule 120: Allow ephemeral ports for return traffic
# When app server calls external APIs the
# responses come back on ephemeral ports
aws ec2 create-network-acl-entry \
  --network-acl-id $PRIVATE_NACL_ID \
  --rule-number 120 \
  --protocol tcp \
  --rule-action allow \
  --ingress \
  --cidr-block 0.0.0.0/0 \
  --port-range From=1024,To=65535 \
  --region $REGION

echo "  Private NACL inbound: Rule 120 - Allow ephemeral ports (1024-65535)"

# OUTBOUND RULES FOR PRIVATE NACL
# Rule 100: Allow HTTP outbound for updates
aws ec2 create-network-acl-entry \
  --network-acl-id $PRIVATE_NACL_ID \
  --rule-number 100 \
  --protocol tcp \
  --rule-action allow \
  --egress \
  --cidr-block 0.0.0.0/0 \
  --port-range From=80,To=80 \
  --region $REGION

echo "  Private NACL outbound: Rule 100 - Allow HTTP (80)"

# Rule 110: Allow HTTPS outbound for updates and APIs
aws ec2 create-network-acl-entry \
  --network-acl-id $PRIVATE_NACL_ID \
  --rule-number 110 \
  --protocol tcp \
  --rule-action allow \
  --egress \
  --cidr-block 0.0.0.0/0 \
  --port-range From=443,To=443 \
  --region $REGION

echo "  Private NACL outbound: Rule 110 - Allow HTTPS (443)"

# Rule 120: Allow ephemeral ports outbound
# Return traffic to web server and bastion
aws ec2 create-network-acl-entry \
  --network-acl-id $PRIVATE_NACL_ID \
  --rule-number 120 \
  --protocol tcp \
  --rule-action allow \
  --egress \
  --cidr-block $VPC_CIDR \
  --port-range From=1024,To=65535 \
  --region $REGION

echo "  Private NACL outbound: Rule 120 - Allow ephemeral ports to VPC"

# Associate private NACL with private subnet
aws ec2 replace-network-acl-association \
  --association-id $(aws ec2 describe-network-acls \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
    --query "NetworkAcls[0].Associations[?SubnetId=='$PRIVATE_SUBNET_ID'].NetworkAclAssociationId" \
    --output text \
    --region $REGION) \
  --network-acl-id $PRIVATE_NACL_ID \
  --region $REGION

echo -e "${GREEN}  ✓ Private NACL associated with private subnet${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Network ACLs complete!${NC}"
echo -e "${GREEN}============================================${NC}"




# ==============================================
# SECTION 8: CREATE IAM ROLES FOR EC2
# ==============================================
echo -e "${YELLOW}Creating IAM Roles...${NC}"

# ------------------------------------------
# TRUST POLICY
# Defines who can assume this role
# We're saying EC2 instances can assume it
# ------------------------------------------
cat > /tmp/ec2-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

echo "  Trust policy document created"





# ------------------------------------------
# WEB SERVER IAM ROLE
# Permissions: Read from S3, Write logs to CloudWatch
# ------------------------------------------
aws iam create-role \
  --role-name three-tier-web-role \
  --assume-role-policy-document file:///tmp/ec2-trust-policy.json \
  --description "IAM role for web server EC2 instance" \
  --region $REGION

echo "  Web server IAM role created"

# Attach policies to web server role
# S3 read access — for serving static assets
aws iam attach-role-policy \
  --role-name three-tier-web-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

# CloudWatch logs — for application logging
aws iam attach-role-policy \
  --role-name three-tier-web-role \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

# SSM access — for secure remote access without SSH
aws iam attach-role-policy \
  --role-name three-tier-web-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

echo "  Web server policies attached: S3ReadOnly, CloudWatchLogs, SSM"

# Create instance profile for web server
# Instance profiles are the container that
# holds the role and attaches it to EC2
aws iam create-instance-profile \
  --instance-profile-name three-tier-web-profile

# Add the role to the instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name three-tier-web-profile \
  --role-name three-tier-web-role

echo -e "${GREEN}  ✓ Web server IAM role and instance profile ready${NC}"

# ------------------------------------------
# APP SERVER IAM ROLE
# Permissions: DynamoDB access, CloudWatch logs
# ------------------------------------------
aws iam create-role \
  --role-name three-tier-app-role \
  --assume-role-policy-document file:///tmp/ec2-trust-policy.json \
  --description "IAM role for app server EC2 instance" \
  --region $REGION

echo "  App server IAM role created"

# Attach policies to app server role
# DynamoDB access — for database operations
aws iam attach-role-policy \
  --role-name three-tier-app-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

# CloudWatch logs — for application logging
aws iam attach-role-policy \
  --role-name three-tier-app-role \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

# SSM access — for secure remote access without SSH
aws iam attach-role-policy \
  --role-name three-tier-app-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

echo "  App server policies attached: DynamoDB, CloudWatchLogs, SSM"

# Create instance profile for app server
aws iam create-instance-profile \
  --instance-profile-name three-tier-app-profile

# Add the role to the instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name three-tier-app-profile \
  --role-name three-tier-app-role

echo -e "${GREEN}  ✓ App server IAM role and instance profile ready${NC}"

# ------------------------------------------
# BASTION HOST IAM ROLE
# Minimal permissions — bastion only needs
# SSM for logging and session management
# ------------------------------------------
aws iam create-role \
  --role-name three-tier-bastion-role \
  --assume-role-policy-document file:///tmp/ec2-trust-policy.json \
  --description "IAM role for bastion host EC2 instance" \
  --region $REGION

echo "  Bastion IAM role created"

# SSM access only — bastion needs minimal permissions
aws iam attach-role-policy \
  --role-name three-tier-bastion-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

echo "  Bastion policies attached: SSM only"

# Create instance profile for bastion
aws iam create-instance-profile \
  --instance-profile-name three-tier-bastion-profile

# Add the role to the instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name three-tier-bastion-profile \
  --role-name three-tier-bastion-role

echo -e "${GREEN}  ✓ Bastion IAM role and instance profile ready${NC}"

# Clean up temp file
rm /tmp/ec2-trust-policy.json

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  IAM Roles and Instance Profiles complete!${NC}"
echo -e "${GREEN}============================================${NC}"


# ==============================================
# SECTION 9: LAUNCH EC2 INSTANCES
# ==============================================
echo -e "${YELLOW}Launching EC2 Instances...${NC}"

# Fetch the latest Amazon Linux 2 AMI ID automatically
# This ensures we always use the most up to date image
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
            "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text \
  --region $REGION)

echo "  Using AMI: $AMI_ID"

# ------------------------------------------
# INSTANCE 1: BASTION HOST
# Lives in PUBLIC subnet
# Only purpose: secure SSH jump server
# ------------------------------------------
echo -e "${YELLOW}  Launching Bastion Host...${NC}"

BASTION_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --key-name three-tier-key \
  --subnet-id $PUBLIC_SUBNET_ID \
  --security-group-ids $BASTION_SG_ID \
  --iam-instance-profile Name=three-tier-bastion-profile \
  --associate-public-ip-address \
  --user-data '#!/bin/bash
    yum update -y
    echo "Bastion host ready" > /var/log/bastion-setup.log' \
  --region $REGION \
  --query "Instances[0].InstanceId" \
  --output text)

echo "  Bastion instance created: $BASTION_ID"

# Name the bastion instance
aws ec2 create-tags \
  --resources $BASTION_ID \
  --tags Key=Name,Value=three-tier-bastion \
         Key=Role,Value=bastion \
         Key=Project,Value=three-tier-vpc \
  --region $REGION

echo -e "${GREEN}  ✓ Bastion Host launched: $BASTION_ID${NC}"

# ------------------------------------------
# INSTANCE 2: WEB SERVER
# Lives in PUBLIC subnet
# Runs a simple web server
# Accessible via HTTP/HTTPS from internet
# ------------------------------------------
echo -e "${YELLOW}  Launching Web Server...${NC}"

WEB_SERVER_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --key-name three-tier-key \
  --subnet-id $PUBLIC_SUBNET_ID \
  --security-group-ids $WEB_SG_ID \
  --iam-instance-profile Name=three-tier-web-profile \
  --associate-public-ip-address \
  --user-data '#!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<html>
      <head><title>Three Tier VPC - Web Server</title></head>
      <body style=\"font-family: Arial; background: #0a0f1e; color: white; 
                    display: flex; justify-content: center; align-items: center; 
                    height: 100vh; margin: 0;\">
        <div style=\"text-align: center;\">
          <h1 style=\"color: #6366f1;\">Three-Tier VPC Architecture</h1>
          <p>Web Server — Running in Public Subnet</p>
          <p style=\"color: #64748b;\">Built with AWS VPC, EC2, Security Groups & IAM</p>
        </div>
      </body>
    </html>" > /var/www/html/index.html
    echo "Web server setup complete" > /var/log/web-setup.log' \
  --region $REGION \
  --query "Instances[0].InstanceId" \
  --output text)

echo "  Web server instance created: $WEB_SERVER_ID"

# Name the web server instance
aws ec2 create-tags \
  --resources $WEB_SERVER_ID \
  --tags Key=Name,Value=three-tier-web-server \
         Key=Role,Value=web \
         Key=Project,Value=three-tier-vpc \
  --region $REGION

echo -e "${GREEN}  ✓ Web Server launched: $WEB_SERVER_ID${NC}"

# ------------------------------------------
# INSTANCE 3: APP SERVER
# Lives in PRIVATE subnet
# No public IP — unreachable from internet
# Only accessible from web server and bastion
# ------------------------------------------
echo -e "${YELLOW}  Launching App Server...${NC}"

APP_SERVER_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --key-name three-tier-key \
  --subnet-id $PRIVATE_SUBNET_ID \
  --security-group-ids $APP_SG_ID \
  --iam-instance-profile Name=three-tier-app-profile \
  --no-associate-public-ip-address \
  --user-data '#!/bin/bash
    yum update -y
    yum install -y nodejs npm
    mkdir -p /app
    cat > /app/server.js << EOF
const http = require("http");
const server = http.createServer((req, res) => {
  res.writeHead(200, {"Content-Type": "application/json"});
  res.end(JSON.stringify({
    status: "healthy",
    server: "app-server",
    tier: "private",
    message: "Three-tier VPC app server running"
  }));
});
server.listen(8080, () => {
  console.log("App server running on port 8080");
});
EOF
    node /app/server.js &
    echo "App server setup complete" > /var/log/app-setup.log' \
  --region $REGION \
  --query "Instances[0].InstanceId" \
  --output text)

echo "  App server instance created: $APP_SERVER_ID"

# Name the app server instance
aws ec2 create-tags \
  --resources $APP_SERVER_ID \
  --tags Key=Name,Value=three-tier-app-server \
         Key=Role,Value=app \
         Key=Project,Value=three-tier-vpc \
  --region $REGION

echo -e "${GREEN}  ✓ App Server launched: $APP_SERVER_ID${NC}"

# Wait for all instances to be running
echo -e "${YELLOW}  Waiting for all instances to be running...${NC}"

aws ec2 wait instance-running \
  --instance-ids $BASTION_ID $WEB_SERVER_ID $APP_SERVER_ID \
  --region $REGION

echo -e "${GREEN}  ✓ All instances are running!${NC}"

# Fetch the public IPs for connecting
BASTION_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $BASTION_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text \
  --region $REGION)

WEB_SERVER_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $WEB_SERVER_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text \
  --region $REGION)

APP_SERVER_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids $APP_SERVER_ID \
  --query "Reservations[0].Instances[0].PrivateIpAddress" \
  --output text \
  --region $REGION)

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  ALL INSTANCES READY!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}  Connection Details:${NC}"
echo "  Bastion Host:   $BASTION_PUBLIC_IP"
echo "  Web Server:     $WEB_SERVER_PUBLIC_IP"
echo "  App Server:     $APP_SERVER_PRIVATE_IP (private only)"
echo ""
echo -e "${YELLOW}  How to connect:${NC}"
echo "  SSH to Bastion:"
echo "  ssh -i ~/.ssh/three-tier-key.pem ec2-user@$BASTION_PUBLIC_IP"
echo ""
echo "  SSH to App Server via Bastion:"
echo "  ssh -i ~/.ssh/three-tier-key.pem -J ec2-user@$BASTION_PUBLIC_IP ec2-user@$APP_SERVER_PRIVATE_IP"
echo ""
echo "  View Web Server:"
echo "  http://$WEB_SERVER_PUBLIC_IP"
echo -e "${GREEN}============================================${NC}"


