# Deploy Lambda Function for Admin Operations (PowerShell)
#
# Script này sẽ:
# 1. Install dependencies và tạo ZIP file
# 2. Tạo IAM Role cho Lambda (nếu chưa có)
# 3. Deploy Lambda function lên AWS
# 4. Tạo API Gateway endpoint với Cognito Authorizer

param(
    [string]$Region = $env:AWS_REGION,
    [string]$UserPoolId = $env:COGNITO_USER_POOL_ID,
    [string]$ApiGatewayId = $env:API_GATEWAY_ID
)

# Configuration
$FunctionName = "AdminManageCoachesFunction"
$Runtime = "nodejs20.x"
$Handler = "manage-coaches.handler"
$RoleName = "AdminOperationsLambdaRole"

# Set defaults
if ([string]::IsNullOrEmpty($Region)) { $Region = "us-east-1" }
if ([string]::IsNullOrEmpty($UserPoolId)) { $UserPoolId = "us-east-1_dskUsnKt3" }

Write-Host "`n=== Deploy Admin Operations Lambda ===`n" -ForegroundColor Green

# Check AWS CLI
try {
    aws --version | Out-Null
} catch {
    Write-Host "Error: AWS CLI is not installed" -ForegroundColor Red
    exit 1
}

# Step 1: Install dependencies
Write-Host "Step 1: Installing dependencies..." -ForegroundColor Green
if (Test-Path "node_modules") {
    Remove-Item -Recurse -Force "node_modules"
}
npm install --production
Write-Host "✓ Dependencies installed" -ForegroundColor Green

# Step 2: Create deployment package
Write-Host "`nStep 2: Creating deployment package..." -ForegroundColor Green
if (Test-Path "manage-coaches.zip") {
    Remove-Item "manage-coaches.zip"
}

# Create ZIP with Lambda code and dependencies
$files = @(
    "manage-coaches.js",
    "package.json",
    "node_modules"
)

# Use PowerShell's Compress-Archive (note: this may not preserve permissions correctly for node_modules)
# For production, consider using 7-Zip or other tools
Write-Host "Creating ZIP file..." -ForegroundColor Yellow
Compress-Archive -Path $files -DestinationPath "manage-coaches.zip" -Force
Write-Host "✓ Deployment package created" -ForegroundColor Green

# Step 3: Create IAM Role
Write-Host "`nStep 3: Creating IAM Role..." -ForegroundColor Green

# Trust policy for Lambda
$TrustPolicy = @"
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
"@

Set-Content -Path "trust-policy.json" -Value $TrustPolicy

# Check if role exists
try {
    $RoleArn = aws iam get-role --role-name $RoleName --query 'Role.Arn' --output text 2>$null
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Host "✓ Using existing IAM Role: $RoleArn" -ForegroundColor Green
} catch {
    Write-Host "Creating new IAM role..." -ForegroundColor Yellow
    $RoleArn = aws iam create-role `
        --role-name $RoleName `
        --assume-role-policy-document file://trust-policy.json `
        --query 'Role.Arn' `
        --output text

    # Attach basic Lambda execution policy
    aws iam attach-role-policy `
        --role-name $RoleName `
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

    # Create inline policy for Cognito admin operations
    $CognitoPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cognito-idp:AdminAddUserToGroup",
        "cognito-idp:AdminRemoveUserFromGroup",
        "cognito-idp:AdminListGroupsForUser",
        "cognito-idp:ListUsersInGroup",
        "cognito-idp:ListUsers"
      ],
      "Resource": "*"
    }
  ]
}
"@
    Set-Content -Path "cognito-policy.json" -Value $CognitoPolicy
    aws iam put-role-policy `
        --role-name $RoleName `
        --policy-name "CognitoAdminOperations" `
        --policy-document file://cognito-policy.json
    Remove-Item "cognito-policy.json"

    Write-Host "✓ IAM Role created with Cognito admin permissions: $RoleArn" -ForegroundColor Green
    Write-Host "Waiting 10 seconds for IAM role to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

Remove-Item "trust-policy.json"

# Step 4: Deploy Lambda function
Write-Host "`nStep 4: Deploying Lambda function..." -ForegroundColor Green

# Check if function exists
try {
    aws lambda get-function --function-name $FunctionName --region $Region 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw }

    Write-Host "Updating existing Lambda function..." -ForegroundColor Yellow
    aws lambda update-function-code `
        --function-name $FunctionName `
        --zip-file fileb://manage-coaches.zip `
        --region $Region

    aws lambda update-function-configuration `
        --function-name $FunctionName `
        --runtime $Runtime `
        --handler $Handler `
        --timeout 30 `
        --memory-size 512 `
        --region $Region `
        --environment "Variables={USER_POOL_ID=$UserPoolId,AWS_REGION=$Region}"

    Write-Host "✓ Lambda function updated" -ForegroundColor Green
} catch {
    Write-Host "Creating new Lambda function..." -ForegroundColor Yellow
    aws lambda create-function `
        --function-name $FunctionName `
        --runtime $Runtime `
        --role $RoleArn `
        --handler $Handler `
        --zip-file fileb://manage-coaches.zip `
        --timeout 30 `
        --memory-size 512 `
        --region $Region `
        --environment "Variables={USER_POOL_ID=$UserPoolId,AWS_REGION=$Region}" `
        --description "Admin operations for managing coaches in Cognito"

    Write-Host "✓ Lambda function created" -ForegroundColor Green
}

# Get Lambda ARN
$LambdaArn = aws lambda get-function `
    --function-name $FunctionName `
    --region $Region `
    --query 'Configuration.FunctionArn' `
    --output text

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "`nLambda Function ARN: " -NoNewline
Write-Host $LambdaArn -ForegroundColor Yellow
Write-Host "User Pool ID: " -NoNewline
Write-Host $UserPoolId -ForegroundColor Yellow

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Tạo API Gateway REST API (nếu chưa có)" -ForegroundColor White
Write-Host "2. Tạo Cognito Authorizer cho API Gateway" -ForegroundColor White
Write-Host "3. Tạo các resources và methods:" -ForegroundColor White
Write-Host "   - GET /admin/coaches - List coaches" -ForegroundColor Gray
Write-Host "   - POST /admin/coaches - Assign coach" -ForegroundColor Gray
Write-Host "   - DELETE /admin/coaches - Remove coach" -ForegroundColor Gray
Write-Host "   - GET /admin/users - List all users" -ForegroundColor Gray
Write-Host "4. Deploy API Gateway stage" -ForegroundColor White
Write-Host "`nXem file API_GATEWAY_SETUP.md để biết chi tiết cách setup API Gateway" -ForegroundColor Yellow

# Cleanup
Remove-Item "manage-coaches.zip"

Write-Host "`nLambda deployment complete!`n" -ForegroundColor Green
