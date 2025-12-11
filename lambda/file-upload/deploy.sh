#!/bin/bash

# Deploy Lambda Function for File Upload to S3
#
# Script này sẽ:
# 1. Install dependencies
# 2. Tạo ZIP file chứa Lambda code
# 3. Update Lambda function code lên AWS
# 4. Update configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
FUNCTION_NAME="image-upload-lambda"
REGION="ap-southeast-1"

echo -e "${GREEN}=== Deploy File Upload Lambda ===${NC}\n"

# Check required tools
command -v aws >/dev/null 2>&1 || { echo -e "${RED}Error: AWS CLI is not installed${NC}" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo -e "${RED}Error: zip is not installed${NC}" >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo -e "${RED}Error: npm is not installed${NC}" >&2; exit 1; }

echo -e "${GREEN}Step 1: Installing dependencies...${NC}"
npm install --production
echo -e "${GREEN}✓ Dependencies installed${NC}"

echo -e "\n${GREEN}Step 2: Creating deployment package...${NC}"
# Remove old zip if exists
rm -f function.zip

# Create zip with code and dependencies
zip -q -r function.zip index.mjs package.json node_modules/
echo -e "${GREEN}✓ Deployment package created ($(du -h function.zip | cut -f1))${NC}"

echo -e "\n${GREEN}Step 3: Updating Lambda function code...${NC}"
aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --zip-file fileb://function.zip \
  --region "$REGION" \
  --output json > /dev/null

echo -e "${GREEN}✓ Lambda code updated${NC}"

echo -e "\n${GREEN}Step 4: Updating Lambda configuration...${NC}"
aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --timeout 10 \
  --memory-size 256 \
  --description "Lambda function for generating pre-signed URLs to upload any file type to S3" \
  --region "$REGION" \
  --output json > /dev/null

echo -e "${GREEN}✓ Configuration updated${NC}"

echo -e "\n${GREEN}Step 5: Waiting for function to be ready...${NC}"
aws lambda wait function-updated \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION"

echo -e "${GREEN}✓ Function is ready${NC}"

# Get function info
FUNCTION_ARN=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --query 'Configuration.FunctionArn' \
  --output text)

echo -e "\n${GREEN}=== Deployment Complete ===${NC}"
echo -e "\nFunction ARN: ${YELLOW}$FUNCTION_ARN${NC}"
echo -e "Region: ${YELLOW}$REGION${NC}"
echo -e "\n${GREEN}Lambda function now supports all file types!${NC}\n"

# Cleanup
rm -f function.zip
echo -e "${GREEN}✓ Cleanup completed${NC}\n"
