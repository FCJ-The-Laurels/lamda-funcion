# Simple Lambda Deployment Script

param(
    [string]$Region = "ap-southeast-1",
    [string]$UserPoolId = "us-east-1_dskUsnKt3"
)

$FunctionName = "AdminManageCoachesFunction"
$RoleName = "AdminOperationsLambdaRole"

Write-Host ""
Write-Host "=== Deploy Admin Operations Lambda ===" -ForegroundColor Green
Write-Host ""

# Step 1: Create deployment package
Write-Host "Step 1: Creating deployment package..." -ForegroundColor Green

if (Test-Path "manage-coaches.zip") {
    Remove-Item "manage-coaches.zip"
}

# Use 7zip if available, otherwise use PowerShell compress
if (Get-Command "7z" -ErrorAction SilentlyContinue) {
    7z a -tzip manage-coaches.zip manage-coaches.js package.json node_modules\ -r | Out-Null
} else {
    Compress-Archive -Path "manage-coaches.js","package.json","node_modules" -DestinationPath "manage-coaches.zip" -Force
}

Write-Host "OK Deployment package created" -ForegroundColor Green

# Step 2: Check/Create IAM Role
Write-Host ""
Write-Host "Step 2: Checking IAM Role..." -ForegroundColor Green

$roleCheck = aws iam get-role --role-name $RoleName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating IAM Role..." -ForegroundColor Yellow

    # Trust policy
    @'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
'@ | Out-File -FilePath "trust.json" -Encoding ASCII -NoNewline

    aws iam create-role --role-name $RoleName --assume-role-policy-document file://trust.json | Out-Null
    aws iam attach-role-policy --role-name $RoleName --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" | Out-Null

    # Cognito policy
    @'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "cognito-idp:AdminAddUserToGroup",
      "cognito-idp:AdminRemoveUserFromGroup",
      "cognito-idp:AdminListGroupsForUser",
      "cognito-idp:ListUsersInGroup",
      "cognito-idp:ListUsers"
    ],
    "Resource": "*"
  }]
}
'@ | Out-File -FilePath "cognito-policy.json" -Encoding ASCII -NoNewline

    aws iam put-role-policy --role-name $RoleName --policy-name "CognitoAdminOps" --policy-document file://cognito-policy.json | Out-Null

    Remove-Item "trust.json" -ErrorAction SilentlyContinue
    Remove-Item "cognito-policy.json" -ErrorAction SilentlyContinue

    Write-Host "OK IAM Role created, waiting 10 seconds..." -ForegroundColor Green
    Start-Sleep -Seconds 10
} else {
    Write-Host "OK IAM Role exists" -ForegroundColor Green
}

$RoleArn = aws iam get-role --role-name $RoleName --query 'Role.Arn' --output text

# Step 3: Deploy Lambda
Write-Host ""
Write-Host "Step 3: Deploying Lambda function..." -ForegroundColor Green

$functionExists = aws lambda get-function --function-name $FunctionName --region $Region 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Updating existing function..." -ForegroundColor Yellow

    aws lambda update-function-code `
        --function-name $FunctionName `
        --zip-file fileb://manage-coaches.zip `
        --region $Region | Out-Null

    aws lambda update-function-configuration `
        --function-name $FunctionName `
        --runtime nodejs20.x `
        --handler manage-coaches.handler `
        --timeout 30 `
        --memory-size 512 `
        --environment "Variables={USER_POOL_ID=$UserPoolId,COGNITO_REGION=us-east-1}" `
        --region $Region | Out-Null

    Write-Host "OK Function updated" -ForegroundColor Green
} else {
    Write-Host "Creating new function..." -ForegroundColor Yellow

    aws lambda create-function `
        --function-name $FunctionName `
        --runtime nodejs20.x `
        --role $RoleArn `
        --handler manage-coaches.handler `
        --zip-file fileb://manage-coaches.zip `
        --timeout 30 `
        --memory-size 512 `
        --environment "Variables={USER_POOL_ID=$UserPoolId,COGNITO_REGION=us-east-1}" `
        --region $Region | Out-Null

    Write-Host "OK Function created" -ForegroundColor Green
}

# Cleanup
Remove-Item "manage-coaches.zip" -ErrorAction SilentlyContinue

# Get Lambda ARN
$LambdaArn = aws lambda get-function --function-name $FunctionName --region $Region --query 'Configuration.FunctionArn' --output text

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Function ARN: " -NoNewline
Write-Host $LambdaArn -ForegroundColor Yellow
Write-Host "User Pool ID: " -NoNewline
Write-Host $UserPoolId -ForegroundColor Yellow
Write-Host "Region: " -NoNewline
Write-Host $Region -ForegroundColor Yellow
Write-Host ""
