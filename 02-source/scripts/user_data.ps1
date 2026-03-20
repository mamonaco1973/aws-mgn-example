<powershell>
$LogFile = "C:\userdata.log"
Start-Transcript -Path $LogFile -Append

Write-Host "user-data start: $(Get-Date -Format 'o')"

$MgnRegion   = "us-east-1"
$SecretName  = "mgn-agent-credentials"

# ================================================================================
# Network Readiness
# Poll until outbound HTTPS is available — user-data runs early and the
# network stack may not be fully ready immediately after boot.
# ================================================================================

Write-Host "Waiting for network..."
$MaxAttempts = 60
for ($i = 1; $i -le $MaxAttempts; $i++) {
  try {
    Invoke-WebRequest -Uri "https://awscli.amazonaws.com/" -UseBasicParsing -TimeoutSec 5 | Out-Null
    Write-Host "Network ready after $($i * 5)s"
    break
  } catch {
    Write-Host "Network not ready, retrying... ($i/$MaxAttempts)"
    Start-Sleep -Seconds 5
  }
}

# ================================================================================
# AWS CLI Install
# Required to read credentials from Secrets Manager via the instance profile.
# ================================================================================

Write-Host "Installing AWS CLI..."
$AwsCliMsi = "C:\Windows\Temp\AWSCLIV2.msi"
Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" `
  -OutFile $AwsCliMsi -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i $AwsCliMsi /qn" -Wait
Remove-Item $AwsCliMsi

# Reload PATH so aws.exe is available in this session.
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "AWS CLI version: $(aws --version)"

# ================================================================================
# IIS Install
# ================================================================================

Write-Host "Installing IIS..."
Install-WindowsFeature -Name Web-Server -IncludeManagementTools

# ================================================================================
# Landing Page
# Landing page text changes after cutover — makes migration success obvious.
# ================================================================================

$Page = "Welcome to IIS - Windows Server 2019 Source VM in us-east-2"
Set-Content -Path "C:\inetpub\wwwroot\iisstart.htm" -Value $Page
Set-Content -Path "C:\inetpub\wwwroot\index.html"   -Value $Page

# ================================================================================
# MGN Agent Installation
#
# Reads agent credentials from Secrets Manager using the EC2 instance profile.
# Downloads the MGN Windows replication agent and registers this server with
# the MGN service in us-east-1.
# ================================================================================

Write-Host "MGN: Fetching agent credentials from Secrets Manager..."

$SecretJson = aws secretsmanager get-secret-value `
  --secret-id $SecretName `
  --region $MgnRegion `
  --query SecretString `
  --output text | ConvertFrom-Json

$AccessKeyId     = $SecretJson.access_key_id
$SecretAccessKey = $SecretJson.secret_access_key

if (-not $AccessKeyId -or -not $SecretAccessKey) {
  Write-Host "MGN: ERROR — failed to parse credentials from secret '$SecretName'."
  Stop-Transcript
  exit 1
}

Write-Host "MGN: Credentials retrieved for key ID: $AccessKeyId"

# --------------------------------------------------------------------------------
# Download MGN Windows installer
# --------------------------------------------------------------------------------

Write-Host "MGN: Downloading replication agent installer..."
$Installer = "C:\Windows\Temp\AwsReplicationWindowsInstaller.exe"
$InstallerUrl = "https://aws-application-migration-service-$MgnRegion.s3.$MgnRegion.amazonaws.com/latest/windows/AwsReplicationWindowsInstaller.exe"

Invoke-WebRequest -Uri $InstallerUrl -OutFile $Installer -UseBasicParsing

# --------------------------------------------------------------------------------
# Run MGN installer
# --------------------------------------------------------------------------------

Write-Host "MGN: Running replication agent installer..."
$Result = Start-Process -FilePath $Installer -ArgumentList @(
  "--region", $MgnRegion,
  "--aws-access-key-id", $AccessKeyId,
  "--aws-secret-access-key", $SecretAccessKey,
  "--no-prompt"
) -Wait -PassThru

Write-Host "MGN: Agent installation complete. Exit: $($Result.ExitCode)"
Remove-Item $Installer

Write-Host "user-data complete: $(Get-Date -Format 'o')"
Stop-Transcript
</powershell>
