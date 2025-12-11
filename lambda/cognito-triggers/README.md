# Cognito Lambda Triggers

Lambda functions để xử lý các events từ AWS Cognito User Pool.

## Overview

Thư mục này chứa Lambda triggers cho Cognito, hiện tại bao gồm:

- **Post Confirmation Trigger**: Tự động tạo user profile trong User Service sau khi user confirm email

## Files

```
.
├── post-confirmation.js     # Lambda handler cho PostConfirmation trigger
├── package.json            # NPM configuration
├── deploy-lambda.sh        # Deploy script (Linux/Mac)
├── deploy-lambda.ps1       # Deploy script (Windows)
├── .gitignore             # Git ignore rules
└── README.md              # Tài liệu này
```

## Quick Start

### 1. Cấu hình Environment Variables

```bash
export AWS_REGION=ap-southeast-1
export COGNITO_USER_POOL_ID=ap-southeast-1_hzot4OSdv
export USER_SERVICE_URL=https://api.yourdomain.com
export USER_SERVICE_API_KEY=your-api-key-here
```

### 2. Deploy

**Linux/Mac**:
```bash
chmod +x deploy-lambda.sh
./deploy-lambda.sh
```

**Windows**:
```powershell
powershell -ExecutionPolicy Bypass -File deploy-lambda.ps1
```

## Documentation

Xem file [COGNITO_LAMBDA_TRIGGER_SETUP.md](../../COGNITO_LAMBDA_TRIGGER_SETUP.md) ở root của project để có hướng dẫn chi tiết.

## Testing

Test Lambda locally:

```javascript
const handler = require('./post-confirmation').handler;

const testEvent = {
  version: "1",
  triggerSource: "PostConfirmation_ConfirmSignUp",
  region: "ap-southeast-1",
  userPoolId: "ap-southeast-1_hzot4OSdv",
  userName: "test-user-id",
  request: {
    userAttributes: {
      email: "test@example.com",
      email_verified: "true",
      name: "Test User"
    }
  },
  response: {}
};

handler(testEvent).then(console.log).catch(console.error);
```

## Monitoring

View CloudWatch logs:

```bash
aws logs tail /aws/lambda/CognitoPostConfirmationTrigger --follow
```

## Support

Nếu có vấn đề, kiểm tra:
1. CloudWatch Logs của Lambda
2. User Service logs
3. Cognito User Pool → Lambda triggers configuration
