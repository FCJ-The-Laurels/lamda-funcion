#!/bin/bash

# Setup Cognito User Pool Groups for RBAC
#
# Script này sẽ tạo 3 groups:
# - admin: Quản trị viên hệ thống
# - coach: Huấn luyện viên hỗ trợ người dùng
# - customer: Người dùng thông thường

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
USER_POOL_ID="${COGNITO_USER_POOL_ID:-ap-southeast-1_hzot4OSdv}"
REGION="${AWS_REGION:-ap-southeast-1}"

echo -e "${GREEN}=== Setup Cognito User Pool Groups ===${NC}\n"

echo "User Pool ID: ${YELLOW}${USER_POOL_ID}${NC}"
echo "Region: ${YELLOW}${REGION}${NC}\n"

# Function to create group
create_group() {
    local group_name=$1
    local description=$2
    local precedence=$3

    echo -e "${GREEN}Creating group: ${YELLOW}${group_name}${NC}"

    # Check if group exists
    existing_group=$(aws cognito-idp get-group \
        --user-pool-id "$USER_POOL_ID" \
        --group-name "$group_name" \
        --region "$REGION" 2>/dev/null || echo "")

    if [ -z "$existing_group" ]; then
        aws cognito-idp create-group \
            --user-pool-id "$USER_POOL_ID" \
            --group-name "$group_name" \
            --description "$description" \
            --precedence "$precedence" \
            --region "$REGION" > /dev/null

        echo -e "${GREEN}✓ Group '${group_name}' created${NC}"
    else
        echo -e "${YELLOW}✓ Group '${group_name}' already exists${NC}"
    fi
}

# Create groups with precedence (lower number = higher priority)
echo -e "${GREEN}Step 1: Creating groups...${NC}\n"

create_group "admin" "System administrators with full access" 1
create_group "coach" "Coaches who support users in their quit journey" 2
create_group "customer" "Regular users of the platform" 3

echo -e "\n${GREEN}=== Groups created successfully ===${NC}\n"

# List all groups
echo -e "${GREEN}Current groups in User Pool:${NC}\n"
aws cognito-idp list-groups \
    --user-pool-id "$USER_POOL_ID" \
    --region "$REGION" \
    --query 'Groups[*].[GroupName,Description,Precedence]' \
    --output table

echo -e "\n${GREEN}=== Setup Complete ===${NC}"
echo -e "\nNext steps:"
echo -e "1. Assign users to groups using: ${YELLOW}aws cognito-idp admin-add-user-to-group${NC}"
echo -e "2. Or use the helper script: ${YELLOW}./assign-user-to-group.sh${NC}"
echo -e "3. Update Lambda trigger to send group info to User Service"
echo -e "4. Verify JWT tokens include cognito:groups claim\n"
