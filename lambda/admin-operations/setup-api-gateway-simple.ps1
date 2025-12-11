# Simple API Gateway Setup for Admin Operations

param(
    [string]$ApiGatewayId = "v7agf76rrh",
    [string]$Region = "ap-southeast-1",
    [string]$UserPoolId = "us-east-1_dskUsnKt3",
    [string]$UserPoolRegion = "us-east-1"
)

Write-Host ""
Write-Host "=== Setup API Gateway for Admin Operations ===" -ForegroundColor Green
Write-Host ""

$accountId = aws sts get-caller-identity --query Account --output text
$lambdaArn = "arn:aws:lambda:${Region}:${accountId}:function:AdminManageCoachesFunction"
$userPoolArn = "arn:aws:cognito-idp:${UserPoolRegion}:${accountId}:userpool/$UserPoolId"

Write-Host "API Gateway: $ApiGatewayId" -ForegroundColor Cyan
Write-Host "Lambda ARN: $lambdaArn" -ForegroundColor Cyan
Write-Host "User Pool ARN: $userPoolArn" -ForegroundColor Cyan
Write-Host ""

# Step 1: Create Cognito Authorizer
Write-Host "Step 1: Creating Cognito Authorizer..." -ForegroundColor Green

$existingAuth = aws apigateway get-authorizers --rest-api-id $ApiGatewayId --region $Region --query 'items[?name==`CognitoAuthorizer`].id' --output text

if ([string]::IsNullOrEmpty($existingAuth)) {
    $authorizerId = aws apigateway create-authorizer `
        --rest-api-id $ApiGatewayId `
        --name "CognitoAuthorizer" `
        --type COGNITO_USER_POOLS `
        --provider-arns $userPoolArn `
        --identity-source "method.request.header.Authorization" `
        --region $Region `
        --query 'id' `
        --output text
    Write-Host "OK Authorizer created: $authorizerId" -ForegroundColor Green
} else {
    $authorizerId = $existingAuth
    Write-Host "OK Using existing authorizer: $authorizerId" -ForegroundColor Green
}

# Step 2: Get root resource
Write-Host ""
Write-Host "Step 2: Creating resource structure..." -ForegroundColor Green

$rootId = aws apigateway get-resources --rest-api-id $ApiGatewayId --region $Region --query 'items[?path==`/`].id' --output text

# Create /admin resource
$adminResourceId = aws apigateway get-resources --rest-api-id $ApiGatewayId --region $Region --query 'items[?pathPart==`admin`].id' --output text

if ([string]::IsNullOrEmpty($adminResourceId)) {
    $adminResourceId = aws apigateway create-resource --rest-api-id $ApiGatewayId --parent-id $rootId --path-part "admin" --region $Region --query 'id' --output text
    Write-Host "OK Created /admin resource: $adminResourceId" -ForegroundColor Green
} else {
    Write-Host "OK Using existing /admin: $adminResourceId" -ForegroundColor Green
}

# Create /admin/coaches resource
$coachesResourceId = aws apigateway get-resources --rest-api-id $ApiGatewayId --region $Region --query 'items[?pathPart==`coaches`].id' --output text

if ([string]::IsNullOrEmpty($coachesResourceId)) {
    $coachesResourceId = aws apigateway create-resource --rest-api-id $ApiGatewayId --parent-id $adminResourceId --path-part "coaches" --region $Region --query 'id' --output text
    Write-Host "OK Created /admin/coaches: $coachesResourceId" -ForegroundColor Green
} else {
    Write-Host "OK Using existing /admin/coaches: $coachesResourceId" -ForegroundColor Green
}

# Step 3: Create methods for /admin/coaches
Write-Host ""
Write-Host "Step 3: Setting up methods..." -ForegroundColor Green

# Helper function
function Add-MethodWithLambda {
    param($ResourceId, $HttpMethod, $Path)

    Write-Host "  Setting up $HttpMethod $Path..." -ForegroundColor Yellow

    aws apigateway put-method --rest-api-id $ApiGatewayId --resource-id $ResourceId --http-method $HttpMethod --authorization-type COGNITO_USER_POOLS --authorizer-id $authorizerId --region $Region 2>&1 | Out-Null

    aws apigateway put-integration --rest-api-id $ApiGatewayId --resource-id $ResourceId --http-method $HttpMethod --type AWS_PROXY --integration-http-method POST --uri "arn:aws:apigateway:${Region}:lambda:path/2015-03-31/functions/$lambdaArn/invocations" --region $Region 2>&1 | Out-Null

    Write-Host "  OK $HttpMethod $Path done" -ForegroundColor Green
}

Add-MethodWithLambda -ResourceId $coachesResourceId -HttpMethod "GET" -Path "/admin/coaches"
Add-MethodWithLambda -ResourceId $coachesResourceId -HttpMethod "POST" -Path "/admin/coaches"
Add-MethodWithLambda -ResourceId $coachesResourceId -HttpMethod "DELETE" -Path "/admin/coaches"

# Step 4: Enable CORS
Write-Host ""
Write-Host "Step 4: Enabling CORS..." -ForegroundColor Green

aws apigateway put-method --rest-api-id $ApiGatewayId --resource-id $coachesResourceId --http-method OPTIONS --authorization-type NONE --region $Region 2>&1 | Out-Null

aws apigateway put-integration --rest-api-id $ApiGatewayId --resource-id $coachesResourceId --http-method OPTIONS --type MOCK --request-templates '{\"application/json\":\"{\\\"statusCode\\\": 200}\"}' --region $Region 2>&1 | Out-Null

aws apigateway put-method-response --rest-api-id $ApiGatewayId --resource-id $coachesResourceId --http-method OPTIONS --status-code 200 --response-parameters '{\"method.response.header.Access-Control-Allow-Headers\"=true,\"method.response.header.Access-Control-Allow-Methods\"=true,\"method.response.header.Access-Control-Allow-Origin\"=true}' --region $Region 2>&1 | Out-Null

aws apigateway put-integration-response --rest-api-id $ApiGatewayId --resource-id $coachesResourceId --http-method OPTIONS --status-code 200 --response-parameters '{\"method.response.header.Access-Control-Allow-Headers\"=\"'"'"'Content-Type,Authorization'"'"'\",\"method.response.header.Access-Control-Allow-Methods\"=\"'"'"'GET,POST,DELETE,OPTIONS'"'"'\",\"method.response.header.Access-Control-Allow-Origin\"=\"'"'"'*'"'"'\"}' --region $Region 2>&1 | Out-Null

Write-Host "OK CORS enabled" -ForegroundColor Green

# Step 5: Grant Lambda permissions
Write-Host ""
Write-Host "Step 5: Granting Lambda permissions..." -ForegroundColor Green

aws lambda remove-permission --function-name AdminManageCoachesFunction --statement-id apigateway-invoke --region $Region 2>&1 | Out-Null

aws lambda add-permission --function-name AdminManageCoachesFunction --statement-id apigateway-invoke --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:${Region}:${accountId}:${ApiGatewayId}/*/*" --region $Region 2>&1 | Out-Null

Write-Host "OK Lambda permissions granted" -ForegroundColor Green

# Step 6: Deploy API
Write-Host ""
Write-Host "Step 6: Deploying API..." -ForegroundColor Green

aws apigateway create-deployment --rest-api-id $ApiGatewayId --stage-name prod --region $Region 2>&1 | Out-Null

Write-Host "OK API deployed" -ForegroundColor Green

# Summary
$apiUrl = "https://${ApiGatewayId}.execute-api.${Region}.amazonaws.com/prod"

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "API Endpoint: " -NoNewline
Write-Host $apiUrl -ForegroundColor Yellow
Write-Host ""
Write-Host "Endpoints available:" -ForegroundColor Cyan
Write-Host "  GET    ${apiUrl}/admin/coaches" -ForegroundColor White
Write-Host "  POST   ${apiUrl}/admin/coaches" -ForegroundColor White
Write-Host "  DELETE ${apiUrl}/admin/coaches" -ForegroundColor White
Write-Host ""
