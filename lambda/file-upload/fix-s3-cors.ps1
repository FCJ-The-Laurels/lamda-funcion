# Fix S3 Bucket CORS and Public Read Policy

param(
    [string]$BucketName = "leaflungs-images-sg",
    [string]$Region = "ap-southeast-1"
)

Write-Host ""
Write-Host "=== Fix S3 Bucket CORS Configuration ===" -ForegroundColor Green
Write-Host ""

# Step 1: Configure CORS
Write-Host "Step 1: Configuring CORS..." -ForegroundColor Green

# Create CORS configuration JSON (inline to avoid BOM issues)
@'
{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "HEAD", "PUT", "POST"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag", "x-amz-server-side-encryption", "x-amz-request-id"],
      "MaxAgeSeconds": 3000
    }
  ]
}
'@ | Out-File -FilePath "cors-config.json" -Encoding ASCII -NoNewline

aws s3api put-bucket-cors --bucket $BucketName --cors-configuration file://cors-config.json --region $Region 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "OK CORS configuration applied" -ForegroundColor Green
} else {
    Write-Host "ERROR Failed to apply CORS" -ForegroundColor Red
}

Remove-Item "cors-config.json" -ErrorAction SilentlyContinue

# Step 2: Disable Public Access Block
Write-Host ""
Write-Host "Step 2: Disabling public access block..." -ForegroundColor Green

aws s3api delete-public-access-block --bucket $BucketName --region $Region 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 254) {
    Write-Host "OK Public access block disabled" -ForegroundColor Green
}

# Step 3: Apply Bucket Policy
Write-Host ""
Write-Host "Step 3: Applying public read bucket policy..." -ForegroundColor Green

$policyContent = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BucketName/*"
    }
  ]
}
"@

$policyContent | Out-File -FilePath "bucket-policy.json" -Encoding ASCII -NoNewline

aws s3api put-bucket-policy --bucket $BucketName --policy file://bucket-policy.json --region $Region 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "OK Bucket policy applied (public read enabled)" -ForegroundColor Green
} else {
    Write-Host "ERROR Failed to apply bucket policy" -ForegroundColor Red
}

Remove-Item "bucket-policy.json" -ErrorAction SilentlyContinue

# Step 4: Verify
Write-Host ""
Write-Host "Step 4: Verifying configuration..." -ForegroundColor Green

$corsResult = aws s3api get-bucket-cors --bucket $BucketName --region $Region 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK CORS configured correctly" -ForegroundColor Green
}

$policyResult = aws s3api get-bucket-policy --bucket $BucketName --region $Region 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK Bucket policy configured correctly" -ForegroundColor Green
}

# Summary
Write-Host ""
Write-Host "=== Configuration Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Bucket: " -NoNewline
Write-Host $BucketName -ForegroundColor Yellow
Write-Host "Region: " -NoNewline
Write-Host $Region -ForegroundColor Yellow
Write-Host ""
Write-Host "Test this URL in browser:" -ForegroundColor Cyan
Write-Host "https://$BucketName.s3.$Region.amazonaws.com/86d44918_z6601691193460_5aee99d36552b445e012fc474d7dd000.jpg" -ForegroundColor White
Write-Host ""
Write-Host "Changes may take 1-2 minutes to propagate globally" -ForegroundColor Yellow
Write-Host ""
