# File Upload Lambda Function

Lambda function để tạo pre-signed URLs cho việc upload **tất cả các loại file** lên S3 bucket `leaflungs-images`.

## 🎯 Tính Năng

- ✅ Hỗ trợ **tất cả loại file**: Images, PDF, Audio, Video, Documents, Text, Archives
- ✅ Pre-signed URLs với thời gian hết hạn 5 phút
- ✅ Custom filename support
- ✅ File size validation (max 50MB)
- ✅ CORS enabled
- ✅ Metadata tracking (timestamp, original filename)
- ✅ Error handling & validation
- ✅ Public URL generation

---

## 📋 Supported File Types

### 🖼️ Images
- JPEG, JPG, PNG, GIF, WEBP, SVG, BMP, TIFF

### 📄 Documents
- PDF, DOC, DOCX, XLS, XLSX, PPT, PPTX

### 📝 Text
- TXT, HTML, CSS, JavaScript, CSV, JSON, XML

### 🎵 Audio
- MP3, WAV, WEBM, OGG, AAC, FLAC, M4A

### 🎬 Video
- MP4, MPEG, WEBM, OGV, MOV, AVI, MKV

### 📦 Archives
- ZIP, RAR, 7Z, TAR, GZ

---

## 🚀 API Usage

### Endpoint
Lambda Function: `image-upload-lambda`
Region: `ap-southeast-1` (Singapore)

### Request Format

**Method**: Invoke Lambda
**Payload**:
```json
{
  "body": {
    "contentType": "image/png",           // Required: MIME type
    "fileSize": 1024000,                  // Optional: File size in bytes
    "fileName": "my-custom-name.png"      // Optional: Custom filename
  }
}
```

### Request Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `contentType` | string | ✅ Yes | MIME type của file (e.g., "image/png", "application/pdf") |
| `fileSize` | number | ❌ No | Kích thước file (bytes). Max: 50MB |
| `fileName` | string | ❌ No | Tên file tùy chỉnh. Sẽ được sanitize và thêm UUID prefix |

### Response Format

**Success (200)**:
```json
{
  "success": true,
  "uploadUrl": "https://leaflungs-images.s3.ap-southeast-1.amazonaws.com/...?X-Amz-...",
  "publicUrl": "https://leaflungs-images.s3.ap-southeast-1.amazonaws.com/uuid.png",
  "key": "uuid.png",
  "expiresIn": 300,
  "metadata": {
    "contentType": "image/png",
    "fileSize": 1024000,
    "bucket": "leaflungs-images"
  }
}
```

**Error (400 - Validation Error)**:
```json
{
  "error": "Validation failed",
  "details": [
    "contentType is required",
    "fileSize must not exceed 50MB"
  ]
}
```

**Error (500 - Server Error)**:
```json
{
  "error": "Internal server error",
  "message": "Error details..."
}
```

---

## 📖 Examples

### 1. Upload PNG Image
```javascript
const payload = {
  body: JSON.stringify({
    contentType: "image/png",
    fileSize: 1024000
  })
};

// Response
{
  "uploadUrl": "https://...",
  "publicUrl": "https://leaflungs-images.s3.ap-southeast-1.amazonaws.com/d32fb10e-a0d7-482d-99f3-21fcea948cfa.png",
  "key": "d32fb10e-a0d7-482d-99f3-21fcea948cfa.png"
}
```

### 2. Upload PDF with Custom Name
```javascript
const payload = {
  body: JSON.stringify({
    contentType: "application/pdf",
    fileSize: 2048000,
    fileName: "my-document.pdf"
  })
};

// Response
{
  "uploadUrl": "https://...",
  "publicUrl": "https://leaflungs-images.s3.ap-southeast-1.amazonaws.com/45b4e276_my-document.pdf",
  "key": "45b4e276_my-document.pdf"
}
```

### 3. Upload MP3 Audio
```javascript
const payload = {
  body: JSON.stringify({
    contentType: "audio/mp3",
    fileSize: 5120000
  })
};

// Response
{
  "uploadUrl": "https://...",
  "publicUrl": "https://leaflungs-images.s3.ap-southeast-1.amazonaws.com/4a352683-0b01-4429-a02d-20fa8b3b844b.mp3",
  "key": "4a352683-0b01-4429-a02d-20fa8b3b844b.mp3"
}
```

### 4. Upload MP4 Video
```javascript
const payload = {
  body: JSON.stringify({
    contentType: "video/mp4",
    fileSize: 20480000
  })
};

// Response
{
  "uploadUrl": "https://...",
  "publicUrl": "https://leaflungs-images.s3.ap-southeast-1.amazonaws.com/290679d6-b9ca-450e-a2d2-e0344607a9cf.mp4",
  "key": "290679d6-b9ca-450e-a2d2-e0344607a9cf.mp4"
}
```

### 5. Upload Text File
```javascript
const payload = {
  body: JSON.stringify({
    contentType: "text/plain",
    fileName: "notes.txt"
  })
};

// Response
{
  "uploadUrl": "https://...",
  "publicUrl": "https://leaflungs-images.s3.ap-southeast-1.amazonaws.com/0252437a_notes.txt",
  "key": "0252437a_notes.txt"
}
```

---

## 🔄 Upload Flow

1. **Request Pre-signed URL**
   - Client gọi Lambda function với `contentType` và optional `fileName`, `fileSize`
   - Lambda validates request và generates pre-signed URL

2. **Upload File to S3**
   - Client sử dụng `uploadUrl` để PUT file lên S3
   - Upload phải hoàn thành trong 5 phút
   - Header `Content-Type` phải match với `contentType` đã request

3. **Access File**
   - Sau khi upload thành công, file có thể được access qua `publicUrl`
   - Hoặc qua CloudFront nếu có cấu hình

### Example Upload với Fetch API

```javascript
// Step 1: Get pre-signed URL
const getUploadUrl = async (file) => {
  const response = await fetch('YOUR_API_GATEWAY_ENDPOINT', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      contentType: file.type,
      fileSize: file.size,
      fileName: file.name
    })
  });

  const data = await response.json();
  return data;
};

// Step 2: Upload file to S3
const uploadFile = async (file) => {
  // Get pre-signed URL
  const { uploadUrl, publicUrl } = await getUploadUrl(file);

  // Upload to S3
  const uploadResponse = await fetch(uploadUrl, {
    method: 'PUT',
    headers: {
      'Content-Type': file.type,
    },
    body: file
  });

  if (uploadResponse.ok) {
    console.log('Upload successful!');
    console.log('File URL:', publicUrl);
    return publicUrl;
  } else {
    throw new Error('Upload failed');
  }
};

// Usage
const fileInput = document.querySelector('input[type="file"]');
fileInput.addEventListener('change', async (e) => {
  const file = e.target.files[0];
  const url = await uploadFile(file);
  console.log('File available at:', url);
});
```

---

## ⚙️ Configuration

### Lambda Configuration
- **Function Name**: `image-upload-lambda`
- **Runtime**: Node.js 20.x
- **Handler**: index.handler
- **Timeout**: 10 seconds
- **Memory**: 256 MB
- **Region**: ap-southeast-1

### Environment Variables
- `S3_BUCKET_NAME`: `leaflungs-images`

### IAM Permissions
Lambda function có quyền:
- `s3:PutObject` - Tạo pre-signed URLs cho upload
- `s3:GetObject` - Read access
- CloudWatch Logs - Logging

### S3 CORS Configuration
```json
{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag", "x-amz-server-side-encryption", "x-amz-request-id"],
      "MaxAgeSeconds": 3000
    }
  ]
}
```

---

## 🛠️ Deployment

### Sử dụng PowerShell Script
```powershell
cd lambda/file-upload
.\deploy.ps1
```

### Sử dụng Bash Script
```bash
cd lambda/file-upload
chmod +x deploy.sh
./deploy.sh
```

### Manual Deployment
```bash
# Install dependencies
npm install --production

# Create deployment package
zip -r function.zip index.mjs package.json node_modules/

# Update Lambda
aws lambda update-function-code \
  --function-name image-upload-lambda \
  --zip-file fileb://function.zip \
  --region ap-southeast-1

# Update configuration
aws lambda update-function-configuration \
  --function-name image-upload-lambda \
  --timeout 10 \
  --memory-size 256 \
  --region ap-southeast-1
```

---

## 🧪 Testing

### Test với AWS CLI
```bash
# Test PNG upload
aws lambda invoke \
  --function-name image-upload-lambda \
  --region ap-southeast-1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"body": "{\"contentType\": \"image/png\", \"fileSize\": 1024000}"}' \
  response.json

# View response
cat response.json
```

### Test Results
```
✅ PNG Image - PASSED
✅ PDF Document - PASSED
✅ MP3 Audio - PASSED
✅ Text File - PASSED
✅ MP4 Video - PASSED
```

---

## 🔒 Security

### File Size Limit
- Maximum: **50MB** per file
- Configurable trong code: `MAX_FILE_SIZE` constant

### File Name Sanitization
- Custom filenames được sanitize (remove special characters)
- UUID prefix được thêm vào để ensure uniqueness
- Maximum length: 100 characters

### CORS
- Hiện tại cho phép tất cả origins (`*`)
- **Production**: Nên restrict origins cụ thể

### S3 Bucket
- Public access **BLOCKED**
- Files chỉ accessible qua pre-signed URLs hoặc authorized access
- Versioning enabled

---

## 📊 Monitoring

### CloudWatch Logs
- Log Group: `/aws/lambda/image-upload-lambda`
- Logs bao gồm:
  - Request events
  - Validation errors
  - Generated URLs
  - Error stack traces

### Metrics
- Invocations
- Duration
- Errors
- Throttles

---

## 🐛 Troubleshooting

### Error: "contentType is required"
- Đảm bảo bạn đã gửi `contentType` trong request body

### Error: "fileSize must not exceed 50MB"
- File quá lớn. Giảm kích thước hoặc tăng `MAX_FILE_SIZE` limit

### Upload failed với CORS error
- Verify S3 bucket CORS configuration
- Check browser console cho chi tiết

### Pre-signed URL expired
- URL có thời hạn 5 phút
- Request URL mới nếu đã hết hạn

---

## 📝 Change Log

### Version 1.0.0 (2025-11-30)
- ✅ Hỗ trợ tất cả loại file (không chỉ images)
- ✅ Custom filename support
- ✅ File size validation
- ✅ CORS headers
- ✅ Error handling
- ✅ Public URL generation
- ✅ Metadata tracking
- ✅ Increased timeout to 10s
- ✅ Increased memory to 256MB

---

## 📧 Support

Nếu gặp vấn đề, vui lòng:
1. Check CloudWatch Logs
2. Verify S3 bucket permissions
3. Test với AWS CLI
4. Contact DevOps team

---

## 📄 License

MIT License - LeafLungs Team
