#!/bin/bash
# ==============================================
# Three-Tier VPC Architecture — AWS CLI Script
# Creates VPC, Subnets, IGW, NAT Gateway,
# Route Tables, Security Groups, and EC2 instances
# ==============================================

set -e  # Stop script if any command fails

echo "Starting VPC infrastructure deployment..."

# ==============================================
# VARIABLES
# ==============================================
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"
AZ="us-east-1a"
MY_IP=$(curl -s https://checkip.amazonaws.com)/32

echo "Your IP: $MY_IP"
echo "Region: $REGION"
echo "============================================"