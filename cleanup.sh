#!/bin/bash
# ==============================================
# Three-Tier VPC Cleanup Script
# Author: Ayotomiwa Ayorinde
#
# Deletes all resources created by
# infrastructure.sh in the correct order
# ==============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REGION="us-east-1"

echo -e "${RED}============================================${NC}"
echo -e "${RED}  THREE-TIER VPC CLEANUP STARTING...${NC}"
echo -e "${RED}  This will delete ALL project resources${NC}"
echo -e "${RED}============================================${NC}"

# Safety confirmation — prevents accidental deletion
read -p "Are you sure you want to delete everything? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Cleanup cancelled."
  exit 0
fi

# ------------------------------------------
# FETCH RESOURCE IDs BY TAG
# We find everything by the Project tag
# so we don't accidentally delete wrong resources
# ------------------------------------------
echo -e "${YELLOW}Finding resources by tag...${NC}"

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=three-tier-vpc" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region $REGION)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
  echo "No VPC found with name three-tier-vpc. Nothing to clean up."
  exit 0
fi

echo "  Found VPC: $VPC_ID"

# Get EC2 Instance IDs by project tag
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=three-tier-vpc" \
            "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text \
  --region $REGION)

# Get NAT Gateway ID
NAT_GW_ID=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" \
           "Name=state,Values=available" \
  --query "NatGateways[0].NatGatewayId" \
  --output text \
  --region $REGION)

# Get Internet Gateway ID
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query "InternetGateways[0].InternetGatewayId" \
  --output text \
  --region $REGION)

# Get Subnet IDs
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].SubnetId" \
  --output text \
  --region $REGION)

# Get Security Group IDs (exclude default)
SG_IDS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=group-name,Values=three-tier-*" \
  --query "SecurityGroups[*].GroupId" \
  --output text \
  --region $REGION)

# Get custom NACL IDs (exclude default)
NACL_IDS=$(aws ec2 describe-network-acls \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=default,Values=false" \
  --query "NetworkAcls[*].NetworkAclId" \
  --output text \
  --region $REGION)

# Get Route Table IDs (exclude main)
RT_IDS=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=tag:Name,Values=three-tier-*" \
  --query "RouteTables[*].RouteTableId" \
  --output text \
  --region $REGION)

echo "  Found instances: $INSTANCE_IDS"
echo "  Found NAT Gateway: $NAT_GW_ID"
echo "  Found Internet Gateway: $IGW_ID"
echo -e "${GREEN}  ✓ All resources found${NC}"

# ------------------------------------------
# STEP 1: TERMINATE EC2 INSTANCES
# ------------------------------------------
if [ ! -z "$INSTANCE_IDS" ]; then
  echo -e "${YELLOW}Terminating EC2 instances...${NC}"
  aws ec2 terminate-instances \
    --instance-ids $INSTANCE_IDS \
    --region $REGION

  echo "  Waiting for instances to terminate..."
  aws ec2 wait instance-terminated \
    --instance-ids $INSTANCE_IDS \
    --region $REGION
  echo -e "${GREEN}  ✓ EC2 instances terminated${NC}"
else
  echo "  No EC2 instances found"
fi

# ------------------------------------------
# STEP 2: DELETE IAM ROLES AND PROFILES
# ------------------------------------------
echo -e "${YELLOW}Deleting IAM roles and instance profiles...${NC}"

for ROLE in three-tier-web-role three-tier-app-role three-tier-bastion-role; do
  PROFILE=${ROLE/role/profile}

  # Detach all policies from role
  POLICIES=$(aws iam list-attached-role-policies \
    --role-name $ROLE \
    --query "AttachedPolicies[*].PolicyArn" \
    --output text 2>/dev/null || echo "")

  for POLICY in $POLICIES; do
    aws iam detach-role-policy \
      --role-name $ROLE \
      --policy-arn $POLICY
  done

  # Remove role from instance profile
  aws iam remove-role-from-instance-profile \
    --instance-profile-name $PROFILE \
    --role-name $ROLE 2>/dev/null || true

  # Delete instance profile
  aws iam delete-instance-profile \
    --instance-profile-name $PROFILE 2>/dev/null || true

  # Delete role
  aws iam delete-role \
    --role-name $ROLE 2>/dev/null || true

  echo "  Deleted: $ROLE and $PROFILE"
done

echo -e "${GREEN}  ✓ IAM roles and profiles deleted${NC}"

# ------------------------------------------
# STEP 3: DELETE NAT GATEWAY
# Most important — stops the hourly charge
# ------------------------------------------
if [ "$NAT_GW_ID" != "None" ] && [ ! -z "$NAT_GW_ID" ]; then
  echo -e "${YELLOW}Deleting NAT Gateway...${NC}"
  aws ec2 delete-nat-gateway \
    --nat-gateway-id $NAT_GW_ID \
    --region $REGION

  echo "  Waiting for NAT Gateway to be deleted..."
  aws ec2 wait nat-gateway-deleted \
    --nat-gateway-ids $NAT_GW_ID \
    --region $REGION
  echo -e "${GREEN}  ✓ NAT Gateway deleted${NC}"

  # Release the Elastic IP
  echo -e "${YELLOW}Releasing Elastic IP...${NC}"
  ALLOC_ID=$(aws ec2 describe-addresses \
    --filters "Name=tag:Name,Values=three-tier-nat-eip" \
    --query "Addresses[0].AllocationId" \
    --output text \
    --region $REGION)

  if [ "$ALLOC_ID" != "None" ] && [ ! -z "$ALLOC_ID" ]; then
    aws ec2 release-address \
      --allocation-id $ALLOC_ID \
      --region $REGION
    echo -e "${GREEN}  ✓ Elastic IP released${NC}"
  fi
fi

# ------------------------------------------
# STEP 4: DELETE SECURITY GROUPS
# ------------------------------------------
if [ ! -z "$SG_IDS" ]; then
  echo -e "${YELLOW}Deleting Security Groups...${NC}"
  for SG_ID in $SG_IDS; do
    aws ec2 delete-security-group \
      --group-id $SG_ID \
      --region $REGION 2>/dev/null || true
    echo "  Deleted security group: $SG_ID"
  done
  echo -e "${GREEN}  ✓ Security groups deleted${NC}"
fi

# ------------------------------------------
# STEP 5: DELETE CUSTOM NACLs
# ------------------------------------------
if [ ! -z "$NACL_IDS" ]; then
  echo -e "${YELLOW}Deleting custom NACLs...${NC}"
  for NACL_ID in $NACL_IDS; do
    aws ec2 delete-network-acl \
      --network-acl-id $NACL_ID \
      --region $REGION 2>/dev/null || true
    echo "  Deleted NACL: $NACL_ID"
  done
  echo -e "${GREEN}  ✓ NACLs deleted${NC}"
fi

# ------------------------------------------
# STEP 6: DETACH AND DELETE INTERNET GATEWAY
# ------------------------------------------
if [ "$IGW_ID" != "None" ] && [ ! -z "$IGW_ID" ]; then
  echo -e "${YELLOW}Detaching and deleting Internet Gateway...${NC}"
  aws ec2 detach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID \
    --region $REGION

  aws ec2 delete-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --region $REGION
  echo -e "${GREEN}  ✓ Internet Gateway deleted${NC}"
fi

# ------------------------------------------
# STEP 7: DELETE ROUTE TABLE ASSOCIATIONS
# THEN DELETE ROUTE TABLES
# ------------------------------------------
if [ ! -z "$RT_IDS" ]; then
  echo -e "${YELLOW}Deleting Route Tables...${NC}"
  for RT_ID in $RT_IDS; do
    # Delete subnet associations first
    ASSOC_IDS=$(aws ec2 describe-route-tables \
      --route-table-ids $RT_ID \
      --query "RouteTables[0].Associations[?Main==\`false\`].RouteTableAssociationId" \
      --output text \
      --region $REGION)

    for ASSOC_ID in $ASSOC_IDS; do
      aws ec2 disassociate-route-table \
        --association-id $ASSOC_ID \
        --region $REGION 2>/dev/null || true
    done

    aws ec2 delete-route-table \
      --route-table-id $RT_ID \
      --region $REGION 2>/dev/null || true
    echo "  Deleted route table: $RT_ID"
  done
  echo -e "${GREEN}  ✓ Route tables deleted${NC}"
fi

# ------------------------------------------
# STEP 8: DELETE SUBNETS
# ------------------------------------------
if [ ! -z "$SUBNET_IDS" ]; then
  echo -e "${YELLOW}Deleting Subnets...${NC}"
  for SUBNET_ID in $SUBNET_IDS; do
    aws ec2 delete-subnet \
      --subnet-id $SUBNET_ID \
      --region $REGION 2>/dev/null || true
    echo "  Deleted subnet: $SUBNET_ID"
  done
  echo -e "${GREEN}  ✓ Subnets deleted${NC}"
fi

# ------------------------------------------
# STEP 9: DELETE KEY PAIR
# ------------------------------------------
echo -e "${YELLOW}Deleting Key Pair...${NC}"
aws ec2 delete-key-pair \
  --key-name three-tier-key \
  --region $REGION 2>/dev/null || true

rm -f ~/.ssh/three-tier-key.pem
echo -e "${GREEN}  ✓ Key pair deleted${NC}"

# ------------------------------------------
# STEP 10: DELETE VPC (must be last)
# ------------------------------------------
echo -e "${YELLOW}Deleting VPC...${NC}"
aws ec2 delete-vpc \
  --vpc-id $VPC_ID \
  --region $REGION

echo -e "${GREEN}  ✓ VPC deleted${NC}"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  CLEANUP COMPLETE!${NC}"
echo -e "${GREEN}  All resources deleted successfully${NC}"
echo -e "${GREEN}  You are no longer being charged${NC}"
echo -e "${GREEN}============================================${NC}"