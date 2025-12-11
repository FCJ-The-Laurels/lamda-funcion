#!/bin/bash

# Setup API Gateway for File Upload Lambda
# Thêm /upload resource vào API Gateway hiện có

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
API_GATEWAY_ID="${API_GATEWAY_ID:-v7agf76rrh}"
REGION="${API_GATEWAY_REGION:-ap-southeast-1}"
LAMBDA_FUNCTION_NAME="image-upload-lambda"
STAGE_NAME="prod"

echo -e "${GREEN}=== Setup API Gateway for File Upload ===${NC}\n"

# Get API Gateway root resource ID
echo -e "${GREEN}Step 1: Getting API Gateway root resource...${NC}"
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
  --rest-api-id "$API_GATEWAY_ID" \
  --region "$REGION" \
  --query 'items[?path==`/`].id' \
  --output text)

echo -e "${GREEN}✓ Root Resource ID: $ROOT_RESOURCE_ID${NC}"

# Create /upload resource
echo -e "\n${GREEN}Step 2: Creating /upload resource...${NC}"

# Check if /upload already exists
UPLOAD_RESOURCE_ID=$(aws apigateway get-resources \
  --rest-api-id "$API_GATEWAY_ID" \
  --region "$REGION" \
  --query 'items[?path==`/upload`].id' \
  --output text 2>/dev/null || echo "")

if [ -z "$UPLOAD_RESOURCE_ID" ]; then
  UPLOAD_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id "$API_GATEWAY_ID" \
    --parent-id "$ROOT_RESOURCE_ID" \
    --path-part "upload" \
    --region "$REGION" \
    --query 'id' \
    --output text)
  echo -e "${GREEN}✓ Created /upload resource: $UPLOAD_RESOURCE_ID${NC}"
else
  echo -e "${YELLOW}✓ /upload resource already exists: $UPLOAD_RESOURCE_ID${NC}"
fi

# Get Lambda ARN
echo -e "\n${GREEN}Step 3: Getting Lambda function ARN...${NC}"
LAMBDA_ARN=$(aws lambda get-function \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --region "$REGION" \
  --query 'Configuration.FunctionArn' \
  --output text)

echo -e "${GREEN}✓ Lambda ARN: $LAMBDA_ARN${NC}"

# Create POST method
echo -e "\n${GREEN}Step 4: Creating POST method...${NC}"

aws apigateway put-method \
  --rest-api-id "$API_GATEWAY_ID" \
  --resource-id "$UPLOAD_RESOURCE_ID" \
  --http-method POST \
  --authorization-type NONE \
  --region "$REGION" 2>/dev/null || echo -e "${YELLOW}Method POST already exists${NC}"

echo -e "${GREEN}✓ POST method created${NC}"

# Setup Lambda integration
echo -e "\n${GREEN}Step 5: Setting up Lambda integration...${NC}"

aws apigateway put-integration \
  --rest-api-id "$API_GATEWAY_ID" \
  --resource-id "$UPLOAD_RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
  --region "$REGION"

echo -e "${GREEN}✓ Lambda integration configured${NC}"

# Setup CORS for OPTIONS method
echo -e "\n${GREEN}Step 6: Setting up CORS (OPTIONS method)...${NC}"

# Create OPTIONS method
aws apigateway put-method \
  --rest-api-id "$API_GATEWAY_ID" \
  --resource-id "$UPLOAD_RESOURCE_ID" \
  --http-method OPTIONS \
  --authorization-type NONE \
  --region "$REGION" 2>/dev/null || echo -e "${YELLOW}Method OPTIONS already exists${NC}"

# Setup mock integration for OPTIONS
aws apigateway put-integration \
  --rest-api-id "$API_GATEWAY_ID" \
  --resource-id "$UPLOAD_RESOURCE_ID" \
  --http-method OPTIONS \
  --type MOCK \
  --request-templates '{"application/json": "{\"statusCode\": 200}"}' \
  --region "$REGION"

# Setup integration response for OPTIONS
aws apigateway put-integration-response \
  --rest-api-id "$API_GATEWAY_ID" \
  --resource-id "$UPLOAD_RESOURCE_ID" \
  --http-method OPTIONS \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Headers": "'"'"'Content-Type,Authorization'"'"'",
    "method.response.header.Access-Control-Allow-Methods": "'"'"'POST,OPTIONS'"'"'",
    "method.response.header.Access-Control-Allow-Origin": "'"'"'*'"'"'"
  }' \
  --region "$REGION"

# Setup method response for OPTIONS
aws apigateway put-method-response \
  --rest-api-id "$API_GATEWAY_ID" \
  --resource-id "$UPLOAD_RESOURCE_ID" \
  --http-method OPTIONS \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Headers": true,
    "method.response.header.Access-Control-Allow-Methods": true,
    "method.response.header.Access-Control-Allow-Origin": true
  }' \
  --region "$REGION"

echo -e "${GREEN}✓ CORS configured${NC}"

# Grant API Gateway permission to invoke Lambda
echo -e "\n${GREEN}Step 7: Granting API Gateway permission to invoke Lambda...${NC}"

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Remove existing permission if exists
aws lambda remove-permission \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --statement-id "apigateway-upload-invoke" \
  --region "$REGION" 2>/dev/null || true

# Add new permission
aws lambda add-permission \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --statement-id "apigateway-upload-invoke" \
  --action "lambda:InvokeFunction" \
  --principal "apigateway.amazonaws.com" \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_GATEWAY_ID}/*/*/upload" \
  --region "$REGION"

echo -e "${GREEN}✓ Permission granted${NC}"

# Deploy to stage
echo -e "\n${GREEN}Step 8: Deploying to ${STAGE_NAME} stage...${NC}"

aws apigateway create-deployment \
  --rest-api-id "$API_GATEWAY_ID" \
  --stage-name "$STAGE_NAME" \
  --region "$REGION"

echo -e "${GREEN}✓ Deployed to ${STAGE_NAME} stage${NC}"

# Get endpoint URL
ENDPOINT_URL="https://${API_GATEWAY_ID}.execute-api.${REGION}.amazonaws.com/${STAGE_NAME}/upload"

echo -e "\n${GREEN}=== Setup Complete ===${NC}"
echo -e "\nFile Upload Endpoint:"
echo -e "${YELLOW}${ENDPOINT_URL}${NC}"
echo -e "\nUpdate your .env file:"
echo -e "${YELLOW}VITE_FILE_UPLOAD_ENDPOINT=${ENDPOINT_URL}${NC}"
echo -e "\nTest with curl:"
echo -e "${YELLOW}curl -X POST ${ENDPOINT_URL} -H 'Content-Type: application/json' -d '{\"body\": \"{\\\"contentType\\\": \\\"image/png\\\"}\"}'${NC}\n"
