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