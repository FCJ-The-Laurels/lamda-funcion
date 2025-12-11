# Setup API Gateway for File Upload Lambda (PowerShell)
# Thêm /upload resource vào API Gateway hiện có

# Configuration
$ApiGatewayId = $env:API_GATEWAY_ID
if (-not $ApiGatewayId) { $ApiGatewayId = "v7agf76rrh" }

$Region = $env:API_GATEWAY_REGION
if (-not $Region) { $Region = "ap-southeast-1" }

$LambdaFunctionName = "image-upload-lambda"
$StageName = "prod"

Write-Host "`n=== Setup API Gateway for File Upload ===`n" -ForegroundColor Green

# Step 1: Get root resource ID
Write-Host "Step 1: Getting API Gateway root resource..." -ForegroundColor Green
$RootResourceId = aws apigateway get-resources `
  --rest-api-id $ApiGatewayId `
  --region $Region `
  --query 'items[?path==`/`].id' `
  --output text

Write-Host "✓ Root Resource ID: $RootResourceId" -ForegroundColor Green

# Step 2: Create /upload resource
Write-Host "`nStep 2: Creating /upload resource..." -ForegroundColor Green

$UploadResourceId = aws apigateway get-resources `
  --rest-api-id $ApiGatewayId `
  --region $Region `
  --query 'items[?path==`/upload`].id' `
  --output text 2>$null

if ([string]::IsNullOrEmpty($UploadResourceId)) {
    $UploadResourceId = aws apigateway create-resource `
      --rest-api-id $ApiGatewayId `
      --parent-id $RootResourceId `
      --path-part "upload" `
      --region $Region `
      --query 'id' `
      --output text
    Write-Host "✓ Created /upload resource: $UploadResourceId" -ForegroundColor Green
} else {
    Write-Host "✓ /upload resource already exists: $UploadResourceId" -ForegroundColor Yellow
}

# Step 3: Get Lambda ARN
Write-Host "`nStep 3: Getting Lambda function ARN..." -ForegroundColor Green
$LambdaArn = aws lambda get-function `
  --function-name $LambdaFunctionName `
  --region $Region `
  --query 'Configuration.FunctionArn' `
  --output text

Write-Host "✓ Lambda ARN: $LambdaArn" -ForegroundColor Green

# Step 4: Create POST method
Write-Host "`nStep 4: Creating POST method..." -ForegroundColor Green

aws apigateway put-method `
  --rest-api-id $ApiGatewayId `
  --resource-id $UploadResourceId `
  --http-method POST `
  --authorization-type NONE `
  --region $Region 2>$null

Write-Host "✓ POST method created" -ForegroundColor Green

# Step 5: Setup Lambda integration
Write-Host "`nStep 5: Setting up Lambda integration..." -ForegroundColor Green

aws apigateway put-integration `
  --rest-api-id $ApiGatewayId `
  --resource-id $UploadResourceId `
  --http-method POST `
  --type AWS_PROXY `
  --integration-http-method POST `
  --uri "arn:aws:apigateway:${Region}:lambda:path/2015-03-31/functions/${LambdaArn}/invocations" `
  --region $Region

Write-Host "✓ Lambda integration configured" -ForegroundColor Green

# Step 6: Setup CORS
Write-Host "`nStep 6: Setting up CORS (OPTIONS method)..." -ForegroundColor Green

# Create OPTIONS method
aws apigateway put-method `
  --rest-api-id $ApiGatewayId `
  --resource-id $UploadResourceId `
  --http-method OPTIONS `
  --authorization-type NONE `
  --region $Region 2>$null

# Mock integration for OPTIONS
aws apigateway put-integration `
  --rest-api-id $ApiGatewayId `
  --resource-id $UploadResourceId `
  --http-method OPTIONS `
  --type MOCK `
  --request-templates '{\"application/json\": \"{\\\"statusCode\\\": 200}\"}' `
  --region $Region

# Integration response for OPTIONS
aws apigateway put-integration-response `
  --rest-api-id $ApiGatewayId `
  --resource-id $UploadResourceId `
  --http-method OPTIONS `
  --status-code 200 `
  --response-parameters '{\"method.response.header.Access-Control-Allow-Headers\": \"'"'"'Content-Type,Authorization'"'"'\",\"method.response.header.Access-Control-Allow-Methods\": \"'"'"'POST,OPTIONS'"'"'\",\"method.response.header.Access-Control-Allow-Origin\": \"'"'"'*'"'"'\"}' `
  --region $Region

# Method response for OPTIONS
aws apigateway put-method-response `
  --rest-api-id $ApiGatewayId `
  --resource-id $UploadResourceId `
  --http-method OPTIONS `
  --status-code 200 `
  --response-parameters '{\"method.response.header.Access-Control-Allow-Headers\": true,\"method.response.header.Access-Control-Allow-Methods\": true,\"method.response.header.Access-Control-Allow-Origin\": true}' `
  --region $Region

Write-Host "✓ CORS configured" -ForegroundColor Green

# Step 7: Grant permission
Write-Host "`nStep 7: Granting API Gateway permission to invoke Lambda..." -ForegroundColor Green

$AccountId = aws sts get-caller-identity --query Account --output text

# Remove existing permission
aws lambda remove-permission `
  --function-name $LambdaFunctionName `
  --statement-id "apigateway-upload-invoke" `
  --region $Region 2>$null

# Add new permission
aws lambda add-permission `
  --function-name $LambdaFunctionName `
  --statement-id "apigateway-upload-invoke" `
  --action "lambda:InvokeFunction" `
  --principal "apigateway.amazonaws.com" `
  --source-arn "arn:aws:execute-api:${Region}:${AccountId}:${ApiGatewayId}/*/*/upload" `
  --region $Region

Write-Host "✓ Permission granted" -ForegroundColor Green

# Step 8: Deploy
Write-Host "`nStep 8: Deploying to $StageName stage..." -ForegroundColor Green

aws apigateway create-deployment `
  --rest-api-id $ApiGatewayId `
  --stage-name $StageName `
  --region $Region

Write-Host "✓ Deployed to $StageName stage" -ForegroundColor Green

# Display endpoint
$EndpointUrl = "https://${ApiGatewayId}.execute-api.${Region}.amazonaws.com/${StageName}/upload"

Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host "`nFile Upload Endpoint:" -ForegroundColor White
Write-Host $EndpointUrl -ForegroundColor Yellow
Write-Host "`nUpdate your .env file:" -ForegroundColor White
Write-Host "VITE_FILE_UPLOAD_ENDPOINT=$EndpointUrl" -ForegroundColor Yellow
Write-Host ""
