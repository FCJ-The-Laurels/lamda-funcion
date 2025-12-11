#!/bin/bash

# Deploy Lambda Function for Cognito Post Confirmation Trigger
#
# Script này sẽ:
# 1. Tạo ZIP file chứa Lambda code
# 2. Tạo IAM Role cho Lambda (nếu chưa có)
# 3. Deploy Lambda function lên AWS
# 4. Configure trigger với Cognito User Pool

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
FUNCTION_NAME="CognitoPostConfirmationTrigger"
RUNTIME="nodejs20.x"
HANDLER="post-confirmation.handler"
ROLE_NAME="CognitoPostConfirmationLambdaRole"
REGION="${AWS_REGION:-ap-southeast-1}"
USER_POOL_ID="${COGNITO_USER_POOL_ID:-ap-southeast-1_hzot4OSdv}"

# User Service Configuration (từ environment variables hoặc nhập thủ công)
USER_SERVICE_URL="${USER_SERVICE_URL:-}"
USER_SERVICE_API_KEY="${USER_SERVICE_API_KEY:-}"

echo -e "${GREEN}=== Deploy Cognito Post Confirmation Lambda ===${NC}\n"

# Check required tools
command -v aws >/dev/null 2>&1 || { echo -e "${RED}Error: AWS CLI is not installed${NC}" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo -e "${RED}Error: zip is not installed${NC}" >&2; exit 1; }

# Prompt for User Service URL if not set
if [ -z "$USER_SERVICE_URL" ]; then
  echo -e "${YELLOW}Enter User Service URL (e.g., https://api.yourdomain.com):${NC}"
  read -r USER_SERVICE_URL
fi

# Prompt for API Key if not set
if [ -z "$USER_SERVICE_API_KEY" ]; then
  echo -e "${YELLOW}Enter User Service API Key (press Enter to skip):${NC}"
  read -r USER_SERVICE_API_KEY
fi

echo -e "\n${GREEN}Step 1: Creating deployment package...${NC}"
zip -q post-confirmation.zip post-confirmation.js package.json
echo -e "${GREEN}✓ Deployment package created${NC}"

echo -e "\n${GREEN}Step 2: Creating IAM Role...${NC}"

# Trust policy for Lambda
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Check if role exists
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null || echo "")

if [ -z "$ROLE_ARN" ]; then
  echo "Creating new IAM role..."
  ROLE_ARN=$(aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://trust-policy.json \
    --query 'Role.Arn' \
    --output text)

  # Attach basic Lambda execution policy
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

  echo -e "${GREEN}✓ IAM Role created: $ROLE_ARN${NC}"
  echo "Waiting 10 seconds for IAM role to propagate..."
  sleep 10
else
  echo -e "${GREEN}✓ Using existing IAM Role: $ROLE_ARN${NC}"
fi

rm trust-policy.json

echo -e "\n${GREEN}Step 3: Deploying Lambda function...${NC}"

# Check if function exists
FUNCTION_EXISTS=$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" 2>/dev/null || echo "")

if [ -z "$FUNCTION_EXISTS" ]; then
  echo "Creating new Lambda function..."
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --role "$ROLE_ARN" \
    --handler "$HANDLER" \
    --zip-file fileb://post-confirmation.zip \
    --timeout 30 \
    --memory-size 256 \
    --region "$REGION" \
    --environment "Variables={USER_SERVICE_URL=$USER_SERVICE_URL,USER_SERVICE_API_KEY=$USER_SERVICE_API_KEY}" \
    --description "Cognito Post Confirmation Trigger - Creates user profile in User Service"
  echo -e "${GREEN}✓ Lambda function created${NC}"
else
  echo "Updating existing Lambda function..."
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file fileb://post-confirmation.zip \
    --region "$REGION"

  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --handler "$HANDLER" \
    --timeout 30 \
    --memory-size 256 \
    --region "$REGION" \
    --environment "Variables={USER_SERVICE_URL=$USER_SERVICE_URL,USER_SERVICE_API_KEY=$USER_SERVICE_API_KEY}"
  echo -e "${GREEN}✓ Lambda function updated${NC}"
fi

echo -e "\n${GREEN}Step 4: Granting Cognito permission to invoke Lambda...${NC}"

# Remove existing permission if exists
aws lambda remove-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "CognitoInvokePermission" \
  --region "$REGION" 2>/dev/null || true

# Add permission for Cognito to invoke Lambda
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id "CognitoInvokePermission" \
  --action "lambda:InvokeFunction" \
  --principal "cognito-idp.amazonaws.com" \
  --source-arn "arn:aws:cognito-idp:${REGION}:$(aws sts get-caller-identity --query Account --output text):userpool/${USER_POOL_ID}" \
  --region "$REGION"

echo -e "${GREEN}✓ Permission granted${NC}"

echo -e "\n${GREEN}Step 5: Configuring Cognito User Pool trigger...${NC}"

# Get Lambda ARN
LAMBDA_ARN=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --query 'Configuration.FunctionArn' \
  --output text)

# Update Cognito User Pool with Lambda trigger
aws cognito-idp update-user-pool \
  --user-pool-id "$USER_POOL_ID" \
  --region "$REGION" \
  --lambda-config "PostConfirmation=$LAMBDA_ARN"

echo -e "${GREEN}✓ Cognito trigger configured${NC}"

# Cleanup
rm post-confirmation.zip

echo -e "\n${GREEN}=== Deployment Complete ===${NC}"
echo -e "\nLambda Function ARN: ${YELLOW}$LAMBDA_ARN${NC}"
echo -e "User Pool ID: ${YELLOW}$USER_POOL_ID${NC}"
echo -e "User Service URL: ${YELLOW}$USER_SERVICE_URL${NC}"
echo -e "\n${GREEN}The Lambda trigger is now active!${NC}"
echo -e "When a user confirms their email, the Lambda will automatically create a profile in your User Service.\n"
