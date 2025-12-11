# Setup Cognito User Pool Groups for RBAC (PowerShell)
#
# Script này sẽ tạo 3 groups:
# - admin: Quản trị viên hệ thống
# - coach: Huấn luyện viên hỗ trợ người dùng
# - customer: Người dùng thông thường

param(
    [string]$UserPoolId = $env:COGNITO_USER_POOL_ID,
    [string]$Region = $env:AWS_REGION
)

# Set defaults
if ([string]::IsNullOrEmpty($UserPoolId)) { $UserPoolId = "ap-southeast-1_hzot4OSdv" }
if ([string]::IsNullOrEmpty($Region)) { $Region = "ap-southeast-1" }

Write-Host "`n=== Setup Cognito User Pool Groups ===`n" -ForegroundColor Green

Write-Host "User Pool ID: " -NoNewline
Write-Host $UserPoolId -ForegroundColor Yellow
Write-Host "Region: " -NoNewline
Write-Host $Region -ForegroundColor Yellow
Write-Host ""

# Function to create group
function Create-CognitoGroup {
    param(
        [string]$GroupName,
        [string]$Description,
        [int]$Precedence
    )

    Write-Host "Creating group: " -NoNewline -ForegroundColor Green
    Write-Host $GroupName -ForegroundColor Yellow

    # Check if group exists
    try {
        aws cognito-idp get-group `
            --user-pool-id $UserPoolId `
            --group-name $GroupName `
            --region $Region 2>$null | Out-Null

        Write-Host "✓ Group '$GroupName' already exists" -ForegroundColor Yellow
    } catch {
        aws cognito-idp create-group `
            --user-pool-id $UserPoolId `
            --group-name $GroupName `
            --description $Description `
            --precedence $Precedence `
            --region $Region | Out-Null

        Write-Host "✓ Group '$GroupName' created" -ForegroundColor Green
    }
}

# Create groups with precedence (lower number = higher priority)
Write-Host "Step 1: Creating groups...`n" -ForegroundColor Green

Create-CognitoGroup -GroupName "admin" -Description "System administrators with full access" -Precedence 1
Create-CognitoGroup -GroupName "coach" -Description "Coaches who support users in their quit journey" -Precedence 2
Create-CognitoGroup -GroupName "customer" -Description "Regular users of the platform" -Precedence 3

Write-Host "`n=== Groups created successfully ===`n" -ForegroundColor Green

# List all groups
Write-Host "Current groups in User Pool:`n" -ForegroundColor Green
aws cognito-idp list-groups `
    --user-pool-id $UserPoolId `
    --region $Region `
    --query 'Groups[*].[GroupName,Description,Precedence]' `
    --output table

Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host "`nNext steps:"
Write-Host "1. Assign users to groups using: " -NoNewline
Write-Host "aws cognito-idp admin-add-user-to-group" -ForegroundColor Yellow
Write-Host "2. Or use the helper script: " -NoNewline
Write-Host ".\assign-user-to-group.ps1" -ForegroundColor Yellow
Write-Host "3. Update Lambda trigger to send group info to User Service"
Write-Host "4. Verify JWT tokens include cognito:groups claim`n"
