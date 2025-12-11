# Helper script to assign user to Cognito group (PowerShell)

param(
    [string]$UserPoolId = $env:COGNITO_USER_POOL_ID,
    [string]$Region = $env:AWS_REGION
)

# Set defaults
if ([string]::IsNullOrEmpty($UserPoolId)) { $UserPoolId = "ap-southeast-1_hzot4OSdv" }
if ([string]::IsNullOrEmpty($Region)) { $Region = "ap-southeast-1" }

Write-Host "`n=== Assign User to Group ===`n" -ForegroundColor Green

# Prompt for username
$Username = Read-Host "Enter username (email or Cognito username)"

# Prompt for group
Write-Host "`nSelect group:" -ForegroundColor Yellow
Write-Host "1. customer (default)"
Write-Host "2. coach"
Write-Host "3. admin"
$GroupChoice = Read-Host "Enter choice (1-3)"

$GroupName = switch ($GroupChoice) {
    "1" { "customer" }
    "2" { "coach" }
    "3" { "admin" }
    default { "customer" }
}

Write-Host "`nAssigning user '$Username' to group '$GroupName'..." -ForegroundColor Green

# Add user to group
aws cognito-idp admin-add-user-to-group `
    --user-pool-id $UserPoolId `
    --username $Username `
    --group-name $GroupName `
    --region $Region

Write-Host "✓ User assigned successfully`n" -ForegroundColor Green

# Show user's groups
Write-Host "User's current groups:" -ForegroundColor Green
aws cognito-idp admin-list-groups-for-user `
    --user-pool-id $UserPoolId `
    --username $Username `
    --region $Region `
    --query 'Groups[*].[GroupName,Description]' `
    --output table

Write-Host ""
