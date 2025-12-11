# Fix CORS for OPTIONS method on /admin/coaches endpoint
# This script configures OPTIONS method with MOCK integration

$ApiId = "v7agf76rrh"
$ResourceId = "lvp9vw"  # /admin/coaches resource ID
$Region = "ap-southeast-1"

Write-Host "Fixing CORS for /admin/coaches OPTIONS method..." -ForegroundColor Cyan

# Step 1: Delete existing OPTIONS method (if exists)
Write-Host "`n1. Deleting existing OPTIONS method..." -ForegroundColor Yellow
try {
    aws apigateway delete-method `
        --rest-api-id $ApiId `
        --resource-id $ResourceId `
        --http-method OPTIONS `
        --region $Region 2>$null
    Write-Host "   Deleted existing OPTIONS method" -ForegroundColor Green
} catch {
    Write-Host "   No existing OPTIONS method to delete" -ForegroundColor Gray
}

# Step 2: Create OPTIONS method with NONE authorization
Write-Host "`n2. Creating OPTIONS method..." -ForegroundColor Yellow
aws apigateway put-method `
    --rest-api-id $ApiId `
    --resource-id $ResourceId `
    --http-method OPTIONS `
    --authorization-type NONE `
    --region $Region | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "   Created OPTIONS method" -ForegroundColor Green
} else {
    Write-Host "   Failed to create OPTIONS method" -ForegroundColor Red
    exit 1
}

# Step 3: Create MOCK integration for OPTIONS
Write-Host "`n3. Creating MOCK integration..." -ForegroundColor Yellow
aws apigateway put-integration `
    --rest-api-id $ApiId `
    --resource-id $ResourceId `
    --http-method OPTIONS `
    --type MOCK `
    --request-templates '{\"application/json\":\"{\\\"statusCode\\\": 200}\"}' `
    --region $Region | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "   Created MOCK integration" -ForegroundColor Green
} else {
    Write-Host "   Failed to create MOCK integration" -ForegroundColor Red
    exit 1
}

# Step 4: Create method response for 200
Write-Host "`n4. Creating method response..." -ForegroundColor Yellow
aws apigateway put-method-response `
    --rest-api-id $ApiId `
    --resource-id $ResourceId `
    --http-method OPTIONS `
    --status-code 200 `
    --response-parameters '{\"method.response.header.Access-Control-Allow-Headers\":false,\"method.response.header.Access-Control-Allow-Methods\":false,\"method.response.header.Access-Control-Allow-Origin\":false}' `
    --region $Region | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "   Created method response" -ForegroundColor Green
} else {
    Write-Host "   Failed to create method response" -ForegroundColor Red
    exit 1
}

# Step 5: Create integration response with CORS headers
Write-Host "`n5. Creating integration response..." -ForegroundColor Yellow
aws apigateway put-integration-response `
    --rest-api-id $ApiId `
    --resource-id $ResourceId `
    --http-method OPTIONS `
    --status-code 200 `
    --response-parameters '{\"method.response.header.Access-Control-Allow-Headers\":\"'"'"'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"'"'\",\"method.response.header.Access-Control-Allow-Methods\":\"'"'"'GET,POST,DELETE,OPTIONS'"'"'\",\"method.response.header.Access-Control-Allow-Origin\":\"'"'"'*'"'"'\"}' `
    --region $Region | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "   Created integration response with CORS headers" -ForegroundColor Green
} else {
    Write-Host "   Failed to create integration response" -ForegroundColor Red
    exit 1
}

# Step 6: Deploy API to prod stage
Write-Host "`n6. Deploying API to prod stage..." -ForegroundColor Yellow
aws apigateway create-deployment `
    --rest-api-id $ApiId `
    --stage-name prod `
    --description "Fix CORS for OPTIONS method" `
    --region $Region | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "   Deployed to prod stage" -ForegroundColor Green
} else {
    Write-Host "   Failed to deploy" -ForegroundColor Red
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CORS Fix Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "OPTIONS method now configured with:" -ForegroundColor White
Write-Host "  - Authorization: NONE" -ForegroundColor Gray
Write-Host "  - Integration: MOCK" -ForegroundColor Gray
Write-Host "  - CORS Headers:" -ForegroundColor Gray
Write-Host "    * Access-Control-Allow-Origin: *" -ForegroundColor Gray
Write-Host "    * Access-Control-Allow-Methods: GET,POST,DELETE,OPTIONS" -ForegroundColor Gray
Write-Host "    * Access-Control-Allow-Headers: Content-Type,Authorization,..." -ForegroundColor Gray
Write-Host ""
Write-Host "API Endpoint: https://$ApiId.execute-api.$Region.amazonaws.com/prod/admin/coaches" -ForegroundColor Cyan
Write-Host ""
