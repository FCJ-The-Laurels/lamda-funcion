# Tự động setup API Gateway cho Admin Operations
# Script này sẽ tạo hoàn chỉnh API Gateway với Cognito Authorizer

param(
    [string]$ApiGatewayId,
    [string]$Region = "ap-southeast-1",
    [string]$UserPoolId = "us-east-1_dskUsnKt3",
    [string]$UserPoolRegion = "us-east-1"
)

Write-Host "`n=== Setup API Gateway for Admin Operations ===`n" -ForegroundColor Green

# Get Account ID
$accountId = aws sts get-caller-identity --query Account --output text
Write-Host "AWS Account ID: $accountId" -ForegroundColor Cyan

# Get Lambda ARN (Lambda should be in same region as API Gateway)
$lambdaArn = "arn:aws:lambda:${Region}:${accountId}:function:AdminManageCoachesFunction"

# User Pool ARN (User Pool is in different region - us-east-1)
$userPoolArn = "arn:aws:cognito-idp:${UserPoolRegion}:${accountId}:userpool/$UserPoolId"

# Sử dụng API Gateway ID hiện có hoặc tạo mới
if ([string]::IsNullOrEmpty($ApiGatewayId)) {
    Write-Host "API Gateway ID not provided. Enter existing API ID or press Enter to create new:" -ForegroundColor Yellow
    $ApiGatewayId = Read-Host "API Gateway ID"

    if ([string]::IsNullOrEmpty($ApiGatewayId)) {
        Write-Host "Creating new API Gateway..." -ForegroundColor Green
        $ApiGatewayId = aws apigateway create-rest-api `
            --name "SmokingCessationAPI" `
            --description "API for smoking cessation platform with admin operations" `
            --endpoint-configuration types=REGIONAL `
            --region $Region `
            --query 'id' `
            --output text
        Write-Host "✓ Created API Gateway: $ApiGatewayId" -ForegroundColor Green
    }
} else {
    Write-Host "Using existing API Gateway: $ApiGatewayId" -ForegroundColor Cyan
}

# Step 1: Create Cognito Authorizer (if not exists)
Write-Host "`nStep 1: Setting up Cognito Authorizer..." -ForegroundColor Green

$existingAuthorizers = aws apigateway get-authorizers `
    --rest-api-id $ApiGatewayId `
    --region $Region `
    --query 'items[?name==`CognitoAuthorizer`].id' `
    --output text

if ([string]::IsNullOrEmpty($existingAuthorizers)) {
    $authorizerId = aws apigateway create-authorizer `
        --rest-api-id $ApiGatewayId `
        --name "CognitoAuthorizer" `
        --type COGNITO_USER_POOLS `
        --provider-arns $userPoolArn `
        --identity-source "method.request.header.Authorization" `
        --region $Region `
        --query 'id' `
        --output text
    Write-Host "✓ Created Cognito Authorizer: $authorizerId" -ForegroundColor Green
} else {
    $authorizerId = $existingAuthorizers
    Write-Host "✓ Using existing Cognito Authorizer: $authorizerId" -ForegroundColor Green
}

# Step 2: Create Resource Structure
Write-Host "`nStep 2: Creating resource structure..." -ForegroundColor Green

# Get root resource
$rootId = aws apigateway get-resources `
    --rest-api-id $ApiGatewayId `
    --region $Region `
    --query 'items[?path==`/`].id' `
    --output text

# Create /admin resource (if not exists)
$adminResourceId = aws apigateway get-resources `
    --rest-api-id $ApiGatewayId `
    --region $Region `
    --query 'items[?pathPart==`admin`].id' `
    --output text

if ([string]::IsNullOrEmpty($adminResourceId)) {
    $adminResourceId = aws apigateway create-resource `
        --rest-api-id $ApiGatewayId `
        --parent-id $rootId `
        --path-part "admin" `
        --region $Region `
        --query 'id' `
        --output text
    Write-Host "✓ Created /admin resource: $adminResourceId" -ForegroundColor Green
} else {
    Write-Host "✓ Using existing /admin resource: $adminResourceId" -ForegroundColor Green
}

# Create /admin/coaches resource
$coachesResourceId = aws apigateway get-resources `
    --rest-api-id $ApiGatewayId `
    --region $Region `
    --query 'items[?pathPart==`coaches`].id' `
    --output text

if ([string]::IsNullOrEmpty($coachesResourceId)) {
    $coachesResourceId = aws apigateway create-resource `
        --rest-api-id $ApiGatewayId `
        --parent-id $adminResourceId `
        --path-part "coaches" `
        --region $Region `
        --query 'id' `
        --output text
    Write-Host "✓ Created /admin/coaches resource: $coachesResourceId" -ForegroundColor Green
} else {
    Write-Host "✓ Using existing /admin/coaches resource: $coachesResourceId" -ForegroundColor Green
}

# Create /admin/users resource
$usersResourceId = aws apigateway get-resources `
    --rest-api-id $ApiGatewayId `
    --region $Region `
    --query 'items[?pathPart==`users`].id' `
    --output text

if ([string]::IsNullOrEmpty($usersResourceId)) {
    $usersResourceId = aws apigateway create-resource `
        --rest-api-id $ApiGatewayId `
        --parent-id $adminResourceId `
        --path-part "users" `
        --region $Region `
        --query 'id' `
        --output text
    Write-Host "✓ Created /admin/users resource: $usersResourceId" -ForegroundColor Green
} else {
    Write-Host "✓ Using existing /admin/users resource: $usersResourceId" -ForegroundColor Green
}

# Step 3: Setup Methods and Integrations
Write-Host "`nStep 3: Setting up methods and Lambda integrations..." -ForegroundColor Green

# Helper function to create method with Lambda integration
function Create-MethodWithLambda {
    param($ResourceId, $HttpMethod, $ResourcePath)

    Write-Host "  Setting up $HttpMethod $ResourcePath..." -ForegroundColor Yellow

    # Create method
    aws apigateway put-method `
        --rest-api-id $ApiGatewayId `
        --resource-id $ResourceId `
        --http-method $HttpMethod `
        --authorization-type COGNITO_USER_POOLS `
        --authorizer-id $authorizerId `
        --region $Region 2>$null

    # Setup Lambda integration (AWS_PROXY)
    aws apigateway put-integration `
        --rest-api-id $ApiGatewayId `
        --resource-id $ResourceId `
        --http-method $HttpMethod `
        --type AWS_PROXY `
        --integration-http-method POST `
        --uri "arn:aws:apigateway:${Region}:lambda:path/2015-03-31/functions/$lambdaArn/invocations" `
        --region $Region 2>$null

    Write-Host "    ✓ $HttpMethod $ResourcePath configured" -ForegroundColor Green
}

# Setup methods for /admin/coaches
Create-MethodWithLambda -ResourceId $coachesResourceId -HttpMethod "GET" -ResourcePath "/admin/coaches"
Create-MethodWithLambda -ResourceId $coachesResourceId -HttpMethod "POST" -ResourcePath "/admin/coaches"
Create-MethodWithLambda -ResourceId $coachesResourceId -HttpMethod "DELETE" -ResourcePath "/admin/coaches"

# Setup methods for /admin/users
Create-MethodWithLambda -ResourceId $usersResourceId -HttpMethod "GET" -ResourcePath "/admin/users"

# Step 4: Setup CORS
Write-Host "`nStep 4: Setting up CORS..." -ForegroundColor Green

function Setup-CORS {
    param($ResourceId, $ResourcePath)

    Write-Host "  Enabling CORS for $ResourcePath..." -ForegroundColor Yellow

    # OPTIONS method
    aws apigateway put-method `
        --rest-api-id $ApiGatewayId `
        --resource-id $ResourceId `
        --http-method OPTIONS `
        --authorization-type NONE `
        --region $Region 2>$null

    # Mock integration
    aws apigateway put-integration `
        --rest-api-id $ApiGatewayId `
        --resource-id $ResourceId `
        --http-method OPTIONS `
        --type MOCK `
        --request-templates '{\"application/json\":\"{\\\"statusCode\\\": 200}\"}' `
        --region $Region 2>$null

    # Method response
    aws apigateway put-method-response `
        --rest-api-id $ApiGatewayId `
        --resource-id $ResourceId `
        --http-method OPTIONS `
        --status-code 200 `
        --response-parameters '{\"method.response.header.Access-Control-Allow-Headers\"=true,\"method.response.header.Access-Control-Allow-Methods\"=true,\"method.response.header.Access-Control-Allow-Origin\"=true}' `
        --region $Region 2>$null

    # Integration response
    aws apigateway put-integration-response `
        --rest-api-id $ApiGatewayId `
        --resource-id $ResourceId `
        --http-method OPTIONS `
        --status-code 200 `
        --response-parameters '{\"method.response.header.Access-Control-Allow-Headers\"=\"'"'"'Content-Type,Authorization'"'"'\",\"method.response.header.Access-Control-Allow-Methods\"=\"'"'"'GET,POST,DELETE,OPTIONS'"'"'\",\"method.response.header.Access-Control-Allow-Origin\"=\"'"'"'*'"'"'\"}' `
        --region $Region 2>$null

    Write-Host "    ✓ CORS enabled for $ResourcePath" -ForegroundColor Green
}

Setup-CORS -ResourceId $coachesResourceId -ResourcePath "/admin/coaches"
Setup-CORS -ResourceId $usersResourceId -ResourcePath "/admin/users"

# Step 5: Grant Lambda Permissions
Write-Host "`nStep 5: Granting API Gateway permission to invoke Lambda..." -ForegroundColor Green

# Remove old permissions if exist
aws lambda remove-permission `
    --function-name AdminManageCoachesFunction `
    --statement-id apigateway-invoke-permission `
    --region $Region 2>$null

# Add permission
aws lambda add-permission `
    --function-name AdminManageCoachesFunction `
    --statement-id apigateway-invoke-permission `
    --action lambda:InvokeFunction `
    --principal apigateway.amazonaws.com `
    --source-arn "arn:aws:execute-api:${Region}:${accountId}:${ApiGatewayId}/*/*" `
    --region $Region

Write-Host "✓ Lambda permissions granted" -ForegroundColor Green

# Step 6: Deploy API
Write-Host "`nStep 6: Deploying API to 'prod' stage..." -ForegroundColor Green

aws apigateway create-deployment `
    --rest-api-id $ApiGatewayId `
    --stage-name prod `
    --stage-description "Production stage" `
    --description "Deployment with admin operations endpoints" `
    --region $Region

Write-Host "✓ API deployed to prod stage" -ForegroundColor Green

# Summary
$apiEndpoint = "https://${ApiGatewayId}.execute-api.${Region}.amazonaws.com/prod"

Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host "`nAPI Gateway Details:" -ForegroundColor Cyan
Write-Host "  API ID: " -NoNewline; Write-Host $ApiGatewayId -ForegroundColor Yellow
Write-Host "  Region: " -NoNewline; Write-Host $Region -ForegroundColor Yellow
Write-Host "  Endpoint: " -NoNewline; Write-Host $apiEndpoint -ForegroundColor Yellow
Write-Host "`nEndpoints:" -ForegroundColor Cyan
Write-Host "  GET    $apiEndpoint/admin/coaches" -ForegroundColor White
Write-Host "  POST   $apiEndpoint/admin/coaches" -ForegroundColor White
Write-Host "  DELETE $apiEndpoint/admin/coaches" -ForegroundColor White
Write-Host "  GET    $apiEndpoint/admin/users" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Cập nhật file src/config/api.config.js với API endpoint:" -ForegroundColor White
Write-Host "   ADMIN_API_URL: '$apiEndpoint'" -ForegroundColor Gray
Write-Host "2. Test API với Postman hoặc curl" -ForegroundColor White
Write-Host "3. Cập nhật frontend ManageCoaches component để gọi API" -ForegroundColor White

Write-Host "`n"
