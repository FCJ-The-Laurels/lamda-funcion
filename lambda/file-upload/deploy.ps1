# Deploy Lambda Function for File Upload to S3 (PowerShell)
#
# Script này sẽ:
# 1. Install dependencies
# 2. Tạo ZIP file chứa Lambda code
# 3. Update Lambda function code lên AWS
# 4. Update configuration

# Configuration
$FunctionName = "image-upload-lambda"
$Region = "ap-southeast-1"

Write-Host "`n=== Deploy File Upload Lambda ===`n" -ForegroundColor Green

# Check AWS CLI
try {
    aws --version | Out-Null
} catch {
    Write-Host "Error: AWS CLI is not installed" -ForegroundColor Red
    exit 1
}

# Check npm
try {
    npm --version | Out-Null
} catch {
    Write-Host "Error: npm is not installed" -ForegroundColor Red
    exit 1
}

Write-Host "Step 1: Installing dependencies..." -ForegroundColor Green
npm install --production
Write-Host "✓ Dependencies installed" -ForegroundColor Green

Write-Host "`nStep 2: Creating deployment package..." -ForegroundColor Green
# Remove old zip if exists
if (Test-Path "function.zip") {
    Remove-Item "function.zip"
}

# Create zip with code and dependencies
Compress-Archive -Path "index.mjs","package.json","node_modules" -DestinationPath "function.zip" -Force
$zipSize = [math]::Round((Get-Item "function.zip").Length / 1MB, 2)
Write-Host "✓ Deployment package created ($zipSize MB)" -ForegroundColor Green

Write-Host "`nStep 3: Updating Lambda function code..." -ForegroundColor Green
aws lambda update-function-code `
  --function-name $FunctionName `
  --zip-file fileb://function.zip `
  --region $Region `
  --output json | Out-Null

Write-Host "✓ Lambda code updated" -ForegroundColor Green

Write-Host "`nStep 4: Updating Lambda configuration..." -ForegroundColor Green
aws lambda update-function-configuration `
  --function-name $FunctionName `
  --timeout 10 `
  --memory-size 256 `
  --description "Lambda function for generating pre-signed URLs to upload any file type to S3" `
  --region $Region `
  --output json | Out-Null

Write-Host "✓ Configuration updated" -ForegroundColor Green

Write-Host "`nStep 5: Waiting for function to be ready..." -ForegroundColor Green
aws lambda wait function-updated `
  --function-name $FunctionName `
  --region $Region

Write-Host "✓ Function is ready" -ForegroundColor Green

# Get function info
$FunctionArn = aws lambda get-function `
  --function-name $FunctionName `
  --region $Region `
  --query 'Configuration.FunctionArn' `
  --output text

Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "`nFunction ARN: " -NoNewline
Write-Host $FunctionArn -ForegroundColor Yellow
Write-Host "Region: " -NoNewline
Write-Host $Region -ForegroundColor Yellow
Write-Host "`nLambda function now supports all file types!" -ForegroundColor Green

# Cleanup
Remove-Item "function.zip"
Write-Host "`n✓ Cleanup completed`n" -ForegroundColor Green
