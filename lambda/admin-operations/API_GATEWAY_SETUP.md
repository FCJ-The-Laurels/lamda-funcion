# API Gateway Setup cho Admin Operations

Hướng dẫn chi tiết cách tạo và cấu hình API Gateway để frontend có thể gọi Lambda function quản lý coaches.

## Tổng quan

Chúng ta sẽ tạo:
- **API Gateway REST API** với Cognito Authorizer
- **4 endpoints** cho admin operations
- **CORS configuration** để frontend có thể gọi từ domain khác
- **Authorization** chỉ admin group mới có quyền gọi

## Bước 1: Tạo REST API

```powershell
# Tạo REST API mới
$apiId = aws apigateway create-rest-api `
    --name "SmokingCessationAdminAPI" `
    --description "API for admin operations" `
    --endpoint-configuration types=REGIONAL `
    --region ap-southeast-1 `
    --query 'id' `
    --output text

Write-Host "API Gateway ID: $apiId"
```

Hoặc sử dụng API Gateway ID hiện có: `v7agf76rrh`

## Bước 2: Tạo Cognito Authorizer

```powershell
$userPoolArn = "arn:aws:cognito-idp:ap-southeast-1:<ACCOUNT_ID>:userpool/ap-southeast-1_hzot4OSdv"

$authorizerId = aws apigateway create-authorizer `
    --rest-api-id $apiId `
    --name "CognitoAuthorizer" `
    --type COGNITO_USER_POOLS `
    --provider-arns $userPoolArn `
    --identity-source "method.request.header.Authorization" `
    --region ap-southeast-1 `
    --query 'id' `
    --output text

Write-Host "Authorizer ID: $authorizerId"
```

## Bước 3: Tạo Resource Structure

```powershell
# Get root resource ID
$rootId = aws apigateway get-resources `
    --rest-api-id $apiId `
    --region ap-southeast-1 `
    --query 'items[?path==`/`].id' `
    --output text

# Tạo /admin resource
$adminResourceId = aws apigateway create-resource `
    --rest-api-id $apiId `
    --parent-id $rootId `
    --path-part "admin" `
    --region ap-southeast-1 `
    --query 'id' `
    --output text

# Tạo /admin/coaches resource
$coachesResourceId = aws apigateway create-resource `
    --rest-api-id $apiId `
    --parent-id $adminResourceId `
    --path-part "coaches" `
    --region ap-southeast-1 `
    --query 'id' `
    --output text

# Tạo /admin/users resource
$usersResourceId = aws apigateway create-resource `
    --rest-api-id $apiId `
    --parent-id $adminResourceId `
    --path-part "users" `
    --region ap-southeast-1 `
    --query 'id' `
    --output text

Write-Host "Resources created:"
Write-Host "  /admin - $adminResourceId"
Write-Host "  /admin/coaches - $coachesResourceId"
Write-Host "  /admin/users - $usersResourceId"
```

## Bước 4: Tạo Methods với Lambda Integration

### 4.1. GET /admin/coaches (List coaches)

```powershell
$lambdaArn = "arn:aws:lambda:ap-southeast-1:<ACCOUNT_ID>:function:AdminManageCoachesFunction"
$accountId = aws sts get-caller-identity --query Account --output text

# Create GET method
aws apigateway put-method `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method GET `
    --authorization-type COGNITO_USER_POOLS `
    --authorizer-id $authorizerId `
    --region ap-southeast-1

# Setup Lambda integration
aws apigateway put-integration `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method GET `
    --type AWS_PROXY `
    --integration-http-method POST `
    --uri "arn:aws:apigateway:ap-southeast-1:lambda:path/2015-03-31/functions/$lambdaArn/invocations" `
    --region ap-southeast-1

# Grant API Gateway permission to invoke Lambda
aws lambda add-permission `
    --function-name AdminManageCoachesFunction `
    --statement-id apigateway-get-coaches `
    --action lambda:InvokeFunction `
    --principal apigateway.amazonaws.com `
    --source-arn "arn:aws:execute-api:ap-southeast-1:${accountId}:${apiId}/*/*" `
    --region ap-southeast-1
```

### 4.2. POST /admin/coaches (Assign coach)

```powershell
# Create POST method
aws apigateway put-method `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method POST `
    --authorization-type COGNITO_USER_POOLS `
    --authorizer-id $authorizerId `
    --region ap-southeast-1

# Setup Lambda integration
aws apigateway put-integration `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method POST `
    --type AWS_PROXY `
    --integration-http-method POST `
    --uri "arn:aws:apigateway:ap-southeast-1:lambda:path/2015-03-31/functions/$lambdaArn/invocations" `
    --region ap-southeast-1
```

### 4.3. DELETE /admin/coaches (Remove coach)

```powershell
# Create DELETE method
aws apigateway put-method `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method DELETE `
    --authorization-type COGNITO_USER_POOLS `
    --authorizer-id $authorizerId `
    --region ap-southeast-1

# Setup Lambda integration
aws apigateway put-integration `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method DELETE `
    --type AWS_PROXY `
    --integration-http-method POST `
    --uri "arn:aws:apigateway:ap-southeast-1:lambda:path/2015-03-31/functions/$lambdaArn/invocations" `
    --region ap-southeast-1
```

### 4.4. GET /admin/users (List all users)

```powershell
# Create GET method
aws apigateway put-method `
    --rest-api-id $apiId `
    --resource-id $usersResourceId `
    --http-method GET `
    --authorization-type COGNITO_USER_POOLS `
    --authorizer-id $authorizerId `
    --region ap-southeast-1

# Setup Lambda integration
aws apigateway put-integration `
    --rest-api-id $apiId `
    --resource-id $usersResourceId `
    --http-method GET `
    --type AWS_PROXY `
    --integration-http-method POST `
    --uri "arn:aws:apigateway:ap-southeast-1:lambda:path/2015-03-31/functions/$lambdaArn/invocations" `
    --region ap-southeast-1
```

## Bước 5: Enable CORS

Cho mỗi resource (coaches và users):

```powershell
# Enable CORS for /admin/coaches
aws apigateway put-method `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method OPTIONS `
    --authorization-type NONE `
    --region ap-southeast-1

aws apigateway put-integration `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method OPTIONS `
    --type MOCK `
    --request-templates '{"application/json":"{\"statusCode\": 200}"}' `
    --region ap-southeast-1

aws apigateway put-method-response `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method OPTIONS `
    --status-code 200 `
    --response-parameters '{"method.response.header.Access-Control-Allow-Headers"=true,"method.response.header.Access-Control-Allow-Methods"=true,"method.response.header.Access-Control-Allow-Origin"=true}' `
    --region ap-southeast-1

aws apigateway put-integration-response `
    --rest-api-id $apiId `
    --resource-id $coachesResourceId `
    --http-method OPTIONS `
    --status-code 200 `
    --response-parameters '{"method.response.header.Access-Control-Allow-Headers"="'"'"'Content-Type,Authorization'"'"'","method.response.header.Access-Control-Allow-Methods"="'"'"'GET,POST,DELETE,OPTIONS'"'"'","method.response.header.Access-Control-Allow-Origin"="'"'"'*'"'"'"}' `
    --region ap-southeast-1

# Làm tương tự cho /admin/users
```

## Bước 6: Deploy API

```powershell
# Tạo deployment
aws apigateway create-deployment `
    --rest-api-id $apiId `
    --stage-name prod `
    --region ap-southeast-1

Write-Host "`nAPI Gateway Endpoint:"
Write-Host "https://$apiId.execute-api.ap-southeast-1.amazonaws.com/prod"
```

## Bước 7: Test API

### Lấy JWT Token từ Cognito

```javascript
// Trong frontend, sau khi login:
const session = await Auth.currentSession();
const jwtToken = session.getIdToken().getJwtToken();
```

### Test với curl

```bash
# List coaches
curl -X GET \
  "https://$apiId.execute-api.ap-southeast-1.amazonaws.com/prod/admin/coaches" \
  -H "Authorization: Bearer $JWT_TOKEN"

# Assign coach
curl -X POST \
  "https://$apiId.execute-api.ap-southeast-1.amazonaws.com/prod/admin/coaches" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com"}'

# Remove coach
curl -X DELETE \
  "https://$apiId.execute-api.ap-southeast-1.amazonaws.com/prod/admin/coaches" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com"}'
```

## Script tự động (All-in-one)

Xem file `setup-api-gateway.ps1` để có script tự động tạo toàn bộ API Gateway.

## Cấu hình Frontend

Sau khi deploy API Gateway, cập nhật file `src/config/api.config.js`:

```javascript
export const API_CONFIG = {
  // ... existing config
  ADMIN_API_URL: 'https://v7agf76rrh.execute-api.ap-southeast-1.amazonaws.com/prod',
};
```

Và sử dụng trong frontend:

```javascript
import { API_CONFIG } from '../config/api.config';
import { Auth } from 'aws-amplify';

// Get JWT token
const session = await Auth.currentSession();
const token = session.getIdToken().getJwtToken();

// Call API
const response = await fetch(`${API_CONFIG.ADMIN_API_URL}/admin/coaches`, {
  method: 'GET',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  },
});
```

## Troubleshooting

### 403 Unauthorized
- Kiểm tra JWT token có hợp lệ không
- Kiểm tra user có thuộc admin group không
- Kiểm tra Cognito Authorizer configuration

### 500 Internal Server Error
- Check Lambda logs trong CloudWatch
- Verify Lambda có quyền Cognito admin operations

### CORS errors
- Verify OPTIONS method được tạo đúng
- Check CORS headers trong Lambda response
- Verify API Gateway CORS configuration
