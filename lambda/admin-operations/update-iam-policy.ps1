# Update IAM policy to add AdminGetUser and AdminCreateUser permissions

$RoleName = "AdminOperationsLambdaRole"
$PolicyName = "CognitoAdminOps"

Write-Host "Updating IAM policy for Lambda role..." -ForegroundColor Cyan

# Create updated policy document
$PolicyDocument = @'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cognito-idp:AdminAddUserToGroup",
        "cognito-idp:AdminRemoveUserFromGroup",
        "cognito-idp:AdminListGroupsForUser",
        "cognito-idp:AdminGetUser",
        "cognito-idp:AdminCreateUser",
        "cognito-idp:ListUsersInGroup",
        "cognito-idp:ListUsers"
      ],
      "Resource": "*"
    }
  ]
}
'@

# Save to file
$PolicyDocument | Out-File -FilePath "policy-update.json" -Encoding ASCII -NoNewline

Write-Host "`nUpdating policy..." -ForegroundColor Yellow
aws iam put-role-policy `
    --role-name $RoleName `
    --policy-name $PolicyName `
    --policy-document file://policy-update.json

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Policy updated successfully!" -ForegroundColor Green
    Write-Host "`nNew permissions added:" -ForegroundColor Cyan
    Write-Host "  - cognito-idp:AdminGetUser" -ForegroundColor Gray
    Write-Host "  - cognito-idp:AdminCreateUser" -ForegroundColor Gray
} else {
    Write-Host "`n❌ Failed to update policy" -ForegroundColor Red
    exit 1
}

# Cleanup
Remove-Item policy-update.json -ErrorAction SilentlyContinue

Write-Host "`nLambda can now:" -ForegroundColor White
Write-Host "  ✓ Check if user exists (AdminGetUser)" -ForegroundColor Green
Write-Host "  ✓ Create new users (AdminCreateUser)" -ForegroundColor Green
Write-Host "  ✓ Send email invites to new coaches" -ForegroundColor Green
