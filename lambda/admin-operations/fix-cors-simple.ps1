# Fix CORS for OPTIONS method - Simplified version

$ApiId = "v7agf76rrh"
$ResourceId = "lvp9vw"  # /admin/coaches
$Region = "ap-southeast-1"

Write-Host "Fixing CORS for /admin/coaches..." -ForegroundColor Cyan

# Step 1: Put integration (MOCK)
Write-Host "`n1. Creating MOCK integration..." -ForegroundColor Yellow
$requestTemplate = '{"application/json":"{\"statusCode\": 200}"}'

aws apigateway put-integration `
    --rest-api-id $ApiId `
    --resource-id $ResourceId `
    --http-method OPTIONS `
    --type MOCK `
    --request-templates $requestTemplate `
    --region $Region

Write-Host ""

# Step 2: Put method response
Write-Host "2. Creating method response..." -ForegroundColor Yellow
aws apigateway put-method-response `
    --rest-api-id $ApiId `
    --resource-id $ResourceId `
    --http-method OPTIONS `
    --status-code 200 `
    --response-parameters "method.response.header.Access-Control-Allow-Headers=false,method.response.header.Access-Control-Allow-Methods=false,method.response.header.Access-Control-Allow-Origin=false" `
    --region $Region

Write-Host ""

# Step 3: Put integration response
Write-Host "3. Creating integration response with CORS headers..." -ForegroundColor Yellow
aws apigateway put-integration-response `
    --rest-api-id $ApiId `
    --resource-id $ResourceId `
    --http-method OPTIONS `
    --status-code 200 `
    --response-parameters "method.response.header.Access-Control-Allow-Headers='Content-Type,Authorization',method.response.header.Access-Control-Allow-Methods='GET,POST,DELETE,OPTIONS',method.response.header.Access-Control-Allow-Origin='*'" `
    --region $Region

Write-Host ""

# Step 4: Deploy
Write-Host "4. Deploying to prod..." -ForegroundColor Yellow
aws apigateway create-deployment `
    --rest-api-id $ApiId `
    --stage-name prod `
    --region $Region

Write-Host "`nDone!" -ForegroundColor Green
