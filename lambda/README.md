# MoMo Payment Lambda Functions

Hai Lambda functions để tích hợp thanh toán MoMo sandbox cho LeafLungs smoking cessation platform.

## Tổng quan

### 1. Payment Creation Lambda (`momo-payment-creation`)
- **Chức năng**: Tạo MoMo payment request khi user chọn gói membership
- **Timeout**: 30 giây (theo yêu cầu MoMo)
- **Memory**: 256 MB
- **Runtime**: Node.js 20.x

### 2. IPN Handler Lambda (`momo-ipn-handler`)
- **Chức năng**: Xử lý IPN callback từ MoMo sau khi thanh toán
- **Timeout**: 15 giây (CRITICAL - MoMo yêu cầu)
- **Memory**: 256 MB
- **Runtime**: Node.js 20.x

## Kiến trúc

```
Frontend
   ↓ (JWT Token)
API Gateway (/payment/momo/create)
   ↓ (Extract userId từ Cognito)
Payment Creation Lambda
   ↓ (Gọi MoMo API)
MoMo Payment Page
   ↓ (User thanh toán)
MoMo IPN Callback → API Gateway (/payment/momo/ipn)
   ↓ (Public endpoint)
IPN Handler Lambda
   ↓ (Validate signature)
   ↓ (Check idempotency)
Backend API (NLB)
   ↓ (Update membership)
PostgreSQL Database
```

## Environment Variables

### Payment Creation Lambda

| Variable | Value | Description |
|----------|-------|-------------|
| `MOMO_PARTNER_CODE` | `MOMO` | Partner code từ MoMo |
| `MOMO_ACCESS_KEY` | `F8BBA842ECF85` | Access key sandbox |
| `MOMO_SECRET_KEY` | `K951B6PE1waDMi640xX08PD3vg6EkVlz` | Secret key để tạo signature |
| `MOMO_ENDPOINT` | `https://test-payment.momo.vn/v2/gateway/api/create` | MoMo API endpoint |
| `BACKEND_API_URL` | `http://leaflungs-userinfo-nlb-3c1d58c7a3d41477.elb.ap-southeast-1.amazonaws.com` | Backend API URL |
| `BACKEND_API_KEY` | `<your-key>` | Internal API key |
| `FRONTEND_REDIRECT_URL` | `https://your-domain.cloudfront.net/payment/callback` | URL redirect sau thanh toán |
| `IPN_URL` | `https://v7agf76rrh.execute-api.ap-southeast-1.amazonaws.com/prod/payment/momo/ipn` | IPN callback URL |

### IPN Handler Lambda

| Variable | Value | Description |
|----------|-------|-------------|
| `MOMO_ACCESS_KEY` | `F8BBA842ECF85` | Access key sandbox |
| `MOMO_SECRET_KEY` | `K951B6PE1waDMi640xX08PD3vg6EkVlz` | Secret key để validate signature |
| `BACKEND_API_URL` | `http://leaflungs-userinfo-nlb-3c1d58c7a3d41477.elb.ap-southeast-1.amazonaws.com` | Backend API URL |
| `BACKEND_API_KEY` | `<your-key>` | Internal API key |

## Deployment

### Prerequisites

1. AWS CLI đã cấu hình
2. Node.js 20.x
3. npm
4. IAM role `LambdaMoMoExecutionRole` (script sẽ tự tạo nếu chưa có)

### Deploy Script

```powershell
# Basic deployment (sử dụng default values)
.\deploy-momo-lambdas.ps1

# Custom deployment với parameters
.\deploy-momo-lambdas.ps1 `
  -Region "ap-southeast-1" `
  -BackendApiKey "your-api-key" `
  -CloudFrontDomain "your-domain.cloudfront.net"
```

### Manual Deployment

#### 1. Package Payment Creation Lambda

```bash
cd lambda/momo-payment-creation
npm install
zip -r function.zip index.mjs node_modules/
```

#### 2. Create Lambda Function

```bash
aws lambda create-function \
  --function-name MoMoPaymentCreationFunction \
  --runtime nodejs20.x \
  --role arn:aws:iam::YOUR_ACCOUNT:role/LambdaMoMoExecutionRole \
  --handler index.handler \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 256 \
  --environment Variables="{MOMO_PARTNER_CODE=MOMO,MOMO_ACCESS_KEY=F8BBA842ECF85,...}" \
  --region ap-southeast-1
```

#### 3. Repeat cho IPN Handler

## API Gateway Configuration

### Endpoint 1: POST /payment/momo/create

- **Authorization**: Cognito User Pool Authorizer (REQUIRED)
- **Integration**: AWS_PROXY → MoMoPaymentCreationFunction
- **CORS**: Enabled

**Request Body**:
```json
{
  "packageType": "PREMIUM",
  "amount": 50000
}
```

**Response**:
```json
{
  "resultCode": 0,
  "payUrl": "https://test-payment.momo.vn/...",
  "orderId": "MOMO1234567890",
  "message": "Success"
}
```

### Endpoint 2: POST /payment/momo/ipn

- **Authorization**: NONE (PUBLIC - MoMo gọi endpoint này)
- **Integration**: AWS_PROXY → MoMoIPNHandlerFunction
- **Response**: 204 No Content

⚠️ **CRITICAL**: Endpoint này PHẢI public và luôn return 204 trong 15 giây

## Security

### 1. Payment Creation
- ✅ Protected bởi Cognito JWT token
- ✅ Extract userId từ `event.requestContext.authorizer.claims.sub`
- ✅ Signature HMAC SHA256 cho MoMo request

### 2. IPN Handler
- ⚠️ Public endpoint (MoMo callback)
- ✅ Signature validation HMAC SHA256 (bảo mật chính)
- ✅ Idempotency check qua `momoTransId` UNIQUE constraint

### Signature Validation

#### Payment Creation - Tạo signature
```javascript
const rawSignature =
  "accessKey=" + accessKey +
  "&amount=" + amount +
  "&extraData=" + extraData +
  "&ipnUrl=" + ipnUrl +
  "&orderId=" + orderId +
  "&orderInfo=" + orderInfo +
  "&partnerCode=" + partnerCode +
  "&redirectUrl=" + redirectUrl +
  "&requestId=" + requestId +
  "&requestType=" + requestType;

const signature = crypto
  .createHmac('sha256', secretKey)
  .update(rawSignature)
  .digest('hex');
```

#### IPN Handler - Validate signature
```javascript
const rawSignature =
  "accessKey=" + accessKey +
  "&amount=" + amount +
  "&extraData=" + extraData +
  "&message=" + message +
  "&orderId=" + orderId +
  "&orderInfo=" + orderInfo +
  "&orderType=" + orderType +
  "&partnerCode=" + partnerCode +
  "&payType=" + payType +
  "&requestId=" + requestId +
  "&responseTime=" + responseTime +
  "&resultCode=" + resultCode +
  "&transId=" + transId;

const expectedSignature = crypto
  .createHmac('sha256', secretKey)
  .update(rawSignature)
  .digest('hex');

if (signature !== expectedSignature) {
  // Invalid signature - reject
}
```

## Idempotency

MoMo có thể retry IPN callback nếu không nhận được response 204 kịp thời.

### Backend API Requirements

Backend cần implement 2 endpoints:

1. **GET /api/user-info/check-transaction/{momoTransId}**
   - Check xem transaction đã được xử lý chưa
   - Return: `{ exists: true/false }`

2. **PATCH /api/user-info/membership**
   - Update membership và momoTransId
   - `momoTransId` phải có UNIQUE constraint
   - Return: 200 OK hoặc 409 Conflict (duplicate)

### Database Schema

```sql
ALTER TABLE user_info
  ADD COLUMN membership VARCHAR(20) DEFAULT 'BASIC',
  ADD COLUMN momoTransId VARCHAR(50) UNIQUE;

CREATE UNIQUE INDEX idx_user_info_momo_trans_id ON user_info(momoTransId);
```

## Testing

### 1. Test Payment Creation

```bash
curl -X POST https://v7agf76rrh.execute-api.ap-southeast-1.amazonaws.com/prod/payment/momo/create \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "packageType": "PREMIUM",
    "amount": 50000
  }'
```

**Expected Response**:
```json
{
  "resultCode": 0,
  "payUrl": "https://test-payment.momo.vn/gw_payment/...",
  "orderId": "MOMO1734345678900"
}
```

### 2. Test IPN Handler

```bash
curl -X POST https://v7agf76rrh.execute-api.ap-southeast-1.amazonaws.com/prod/payment/momo/ipn \
  -H "Content-Type: application/json" \
  -d '{
    "partnerCode": "MOMO",
    "orderId": "MOMO1234567890",
    "requestId": "MOMO1234567890",
    "amount": 50000,
    "transId": "2889556006",
    "resultCode": 0,
    "message": "Success",
    "orderType": "momo_wallet",
    "payType": "qr",
    "responseTime": 1734345678900,
    "extraData": "eyJ1c2VySWQiOiJ0ZXN0LXVzZXItaWQiLCJwYWNrYWdlVHlwZSI6IlBSRU1JVU0ifQ==",
    "signature": "..."
  }'
```

**Expected Response**: HTTP 204 No Content

### 3. Check CloudWatch Logs

```bash
# Payment Creation logs
aws logs tail /aws/lambda/MoMoPaymentCreationFunction --follow

# IPN Handler logs
aws logs tail /aws/lambda/MoMoIPNHandlerFunction --follow
```

## Troubleshooting

### Payment Creation Issues

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| 401 Unauthorized | Missing JWT token | Check Cognito authorizer config |
| 504 Timeout | MoMo API slow | Check network, increase timeout |
| Invalid signature | Wrong secret key | Verify MOMO_SECRET_KEY |
| No payUrl returned | MoMo API error | Check CloudWatch logs |

### IPN Handler Issues

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| Signature invalid | Wrong secret key or raw string order | Verify signature validation logic |
| Duplicate update | No idempotency check | Check momoTransId UNIQUE constraint |
| Backend API error | Wrong API key or URL | Verify BACKEND_API_KEY and URL |
| Timeout > 15s | Slow backend response | Optimize backend API, check DB connection |

### Common Errors

#### 1. "Missing userId in authorizer context"
- **Cause**: Cognito authorizer không được config đúng
- **Fix**: Kiểm tra API Gateway authorizer settings

#### 2. "Transaction already processed"
- **Cause**: MoMo retry IPN callback
- **Fix**: Normal behavior - idempotency working correctly

#### 3. "Invalid signature - possible security breach"
- **Cause**: Sai secret key hoặc raw signature string
- **Fix**: Double-check MOMO_SECRET_KEY và thứ tự fields trong raw signature

## Monitoring

### CloudWatch Metrics

Monitor these metrics:
- Lambda invocation count
- Lambda error rate
- Lambda duration
- API Gateway 4xx/5xx errors

### Alarms

Recommended alarms:
```bash
# Lambda errors
aws cloudwatch put-metric-alarm \
  --alarm-name MoMoPaymentCreation-Errors \
  --alarm-description "Alert when payment creation errors > 5" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=MoMoPaymentCreationFunction
```

### Logging

Both Lambda functions log extensively:
- ✅ Request/response payloads
- ✅ Signature validation steps
- ✅ API call results
- ✅ Error details

Log format:
- Incoming request
- User information
- Signature validation
- External API calls
- Success messages
- Error messages
- Warnings

## Production Checklist

Trước khi lên production:

- [ ] Update MoMo credentials sang production:
  - [ ] Partner Code
  - [ ] Access Key
  - [ ] Secret Key
  - [ ] Endpoint: `https://payment.momo.vn/v2/gateway/api/create`
- [ ] Update FRONTEND_REDIRECT_URL với domain production
- [ ] Update IPN_URL với production API Gateway
- [ ] Update BACKEND_API_KEY với production key
- [ ] Setup CloudWatch alarms
- [ ] Register IPN URL với MoMo
- [ ] Test end-to-end payment flow
- [ ] Verify idempotency
- [ ] Load test (nếu cần)
- [ ] Document runbook cho on-call team

## Support

- MoMo Developer Portal: https://developers.momo.vn
- MoMo GitHub: https://github.com/momo-wallet/payment
- AWS Lambda Docs: https://docs.aws.amazon.com/lambda/
- CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/

## License

Internal use only - LeafLungs Platform
