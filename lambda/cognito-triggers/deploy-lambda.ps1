# Deploy Lambda Function for Cognito Post Confirmation Trigger (PowerShell)
#
# Script này sẽ:
# 1. Tạo ZIP file chứa Lambda code
# 2. Tạo IAM Role cho Lambda (nếu chưa có)
# 3. Deploy Lambda function lên AWS
# 4. Configure trigger với Cognito User Pool

param(
    [string]$Region = $env:AWS_REGION,
    [string]$UserPoolId = $env:COGNITO_USER_POOL_ID,
    [string]$UserServiceUrl = $env:USER_SERVICE_URL,
    [string]$UserServiceApiKey = $env:USER_SERVICE_API_KEY
)

# Configuration
$FunctionName = "CognitoPostConfirmationTrigger"
$Runtime = "nodejs20.x"
$Handler = "post-confirmation.handler"
$RoleName = "CognitoPostConfirmationLambdaRole"

# Set defaults
if ([string]::IsNullOrEmpty($Region)) { $Region = "us-east-1" }
if ([string]::IsNullOrEmpty($UserPoolId)) { $UserPoolId = "us-east-1_dskUsnKt3" }

Write-Host "`n=== Deploy Cognito Post Confirmation Lambda ===`n" -ForegroundColor Green

# Check AWS CLI
try {
    aws --version | Out-Null
} catch {
    Write-Host "Error: AWS CLI is not installed" -ForegroundColor Red
    exit 1
}

# Prompt for User Service URL if not set
if ([string]::IsNullOrEmpty($UserServiceUrl)) {
    $UserServiceUrl = Read-Host "Enter User Service URL (e.g., https://api.yourdomain.com)"
}

# Prompt for API Key if not set
if ([string]::IsNullOrEmpty($UserServiceApiKey)) {
    $UserServiceApiKey = Read-Host "Enter User Service API Key (press Enter to skip)"
}

Write-Host "`nStep 1: Creating deployment package..." -ForegroundColor Green
if (Test-Path "post-confirmation.zip") {
    Remove-Item "post-confirmation.zip"
}
Compress-Archive -Path "post-confirmation.js","package.json" -DestinationPath "post-confirmation.zip" -Force
Write-Host "✓ Deployment package created" -ForegroundColor Green

Write-Host "`nStep 2: Creating IAM Role..." -ForegroundColor Green

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

    # Create inline policy for Cognito group management
    $CognitoPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cognito-idp:AdminAddUserToGroup",
        "cognito-idp:AdminListGroupsForUser"
      ],
      "Resource": "*"
    }
  ]
}
"@
    Set-Content -Path "cognito-policy.json" -Value $CognitoPolicy
    aws iam put-role-policy `
        --role-name $RoleName `
        --policy-name "CognitoGroupManagement" `
        --policy-document file://cognito-policy.json
    Remove-Item "cognito-policy.json"

    Write-Host "✓ IAM Role created with Cognito permissions: $RoleArn" -ForegroundColor Green
    Write-Host "Waiting 10 seconds for IAM role to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

Remove-Item "trust-policy.json"

Write-Host "`nStep 3: Deploying Lambda function..." -ForegroundColor Green

# Check if function exists
try {
    aws lambda get-function --function-name $FunctionName --region $Region 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw }

    Write-Host "Updating existing Lambda function..." -ForegroundColor Yellow
    aws lambda update-function-code `
        --function-name $FunctionName `
        --zip-file fileb://post-confirmation.zip `
        --region $Region

    aws lambda update-function-configuration `
        --function-name $FunctionName `
        --runtime $Runtime `
        --handler $Handler `
        --timeout 30 `
        --memory-size 256 `
        --region $Region `
        --environment "Variables={USER_SERVICE_URL=$UserServiceUrl,USER_SERVICE_API_KEY=$UserServiceApiKey,AUTO_ASSIGN_GROUP=true,DEFAULT_USER_GROUP=customer,AWS_REGION=$Region}"

    Write-Host "✓ Lambda function updated" -ForegroundColor Green
} catch {
    Write-Host "Creating new Lambda function..." -ForegroundColor Yellow
    aws lambda create-function `
        --function-name $FunctionName `
        --runtime $Runtime `
        --role $RoleArn `
        --handler $Handler `
        --zip-file fileb://post-confirmation.zip `
        --timeout 30 `
        --memory-size 256 `
        --region $Region `
        --environment "Variables={USER_SERVICE_URL=$UserServiceUrl,USER_SERVICE_API_KEY=$UserServiceApiKey,AUTO_ASSIGN_GROUP=true,DEFAULT_USER_GROUP=customer,AWS_REGION=$Region}" `
        --description "Cognito Post Confirmation Trigger - Creates user profile and assigns to customer group"

    Write-Host "✓ Lambda function created" -ForegroundColor Green
}

Write-Host "`nStep 4: Granting Cognito permission to invoke Lambda..." -ForegroundColor Green

# Get AWS Account ID
$AccountId = aws sts get-caller-identity --query Account --output text

# Remove existing permission if exists
aws lambda remove-permission `
    --function-name $FunctionName `
    --statement-id "CognitoInvokePermission" `
    --region $Region 2>$null | Out-Null

# Add permission for Cognito to invoke Lambda
aws lambda add-permission `
    --function-name $FunctionName `
    --statement-id "CognitoInvokePermission" `
    --action "lambda:InvokeFunction" `
    --principal "cognito-idp.amazonaws.com" `
    --source-arn "arn:aws:cognito-idp:${Region}:${AccountId}:userpool/$UserPoolId" `
    --region $Region

Write-Host "✓ Permission granted" -ForegroundColor Green

Write-Host "`nStep 5: Configuring Cognito User Pool trigger..." -ForegroundColor Green

# Get Lambda ARN
$LambdaArn = aws lambda get-function `
    --function-name $FunctionName `
    --region $Region `
    --query 'Configuration.FunctionArn' `
    --output text

# Update Cognito User Pool with Lambda trigger
aws cognito-idp update-user-pool `
    --user-pool-id $UserPoolId `
    --region $Region `
    --lambda-config "PostConfirmation=$LambdaArn"

Write-Host "✓ Cognito trigger configured" -ForegroundColor Green

# Cleanup
Remove-Item "post-confirmation.zip"

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "`nLambda Function ARN: " -NoNewline
Write-Host $LambdaArn -ForegroundColor Yellow
Write-Host "User Pool ID: " -NoNewline
Write-Host $UserPoolId -ForegroundColor Yellow
Write-Host "User Service URL: " -NoNewline
Write-Host $UserServiceUrl -ForegroundColor Yellow
Write-Host "`nThe Lambda trigger is now active!" -ForegroundColor Green
Write-Host "When a user confirms their email, the Lambda will automatically create a profile in your User Service.`n"
