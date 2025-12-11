#!/bin/bash

# Helper script to assign user to Cognito group

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

USER_POOL_ID="${COGNITO_USER_POOL_ID:-ap-southeast-1_hzot4OSdv}"
REGION="${AWS_REGION:-ap-southeast-1}"

echo -e "${GREEN}=== Assign User to Group ===${NC}\n"

# Prompt for username
echo -e "${YELLOW}Enter username (email or Cognito username):${NC}"
read -r USERNAME

# Prompt for group
echo -e "\n${YELLOW}Select group:${NC}"
echo "1. customer (default)"
echo "2. coach"
echo "3. admin"
read -p "Enter choice (1-3): " GROUP_CHOICE

case $GROUP_CHOICE in
    1) GROUP_NAME="customer" ;;
    2) GROUP_NAME="coach" ;;
    3) GROUP_NAME="admin" ;;
    *) GROUP_NAME="customer" ;;
esac

echo -e "\n${GREEN}Assigning user '${USERNAME}' to group '${GROUP_NAME}'...${NC}"

# Add user to group
aws cognito-idp admin-add-user-to-group \
    --user-pool-id "$USER_POOL_ID" \
    --username "$USERNAME" \
    --group-name "$GROUP_NAME" \
    --region "$REGION"

echo -e "${GREEN}✓ User assigned successfully${NC}\n"

# Show user's groups
echo -e "${GREEN}User's current groups:${NC}"
aws cognito-idp admin-list-groups-for-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$USERNAME" \
    --region "$REGION" \
    --query 'Groups[*].[GroupName,Description]' \
    --output table

echo ""
