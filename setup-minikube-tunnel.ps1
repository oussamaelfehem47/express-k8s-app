# PowerShell script to set up Minikube tunnel with ngrok
# This exposes your local Minikube cluster to the internet for GitHub Actions

param(
    [string]$MinikubePort = "58093",
    [string]$NgrokAuthToken = ""
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Minikube Tunnel Setup with ngrok" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Minikube is running
Write-Host "1. Checking Minikube status..."
$minikubeStatus = minikube status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "   Error: Minikube is not running. Please start it first:" -ForegroundColor Red
    Write-Host "   minikube start" -ForegroundColor Yellow
    exit 1
}
Write-Host "   Minikube is running" -ForegroundColor Green

# Get Minikube API server URL
Write-Host ""
Write-Host "2. Getting Minikube API server URL..."
$minikubeIP = minikube ip
$minikubeURL = "https://127.0.0.1:$MinikubePort"
Write-Host "   Minikube URL: $minikubeURL" -ForegroundColor Green

# Check if ngrok is installed
Write-Host ""
Write-Host "3. Checking ngrok installation..."
$ngrokInstalled = $false
try {
    $null = ngrok version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $ngrokInstalled = $true
        Write-Host "   ngrok is installed" -ForegroundColor Green
    }
} catch {
    $ngrokInstalled = $false
}

if (-not $ngrokInstalled) {
    Write-Host "   ngrok is not installed" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Please install ngrok:" -ForegroundColor Yellow
    Write-Host "   1. Download from: https://ngrok.com/download" -ForegroundColor White
    Write-Host "   2. Extract and add to PATH, or run from the extracted folder" -ForegroundColor White
    Write-Host "   3. Sign up for a free account at: https://dashboard.ngrok.com/signup" -ForegroundColor White
    Write-Host "   4. Get your authtoken from: https://dashboard.ngrok.com/get-started/your-authtoken" -ForegroundColor White
    Write-Host ""
    Write-Host "   Then run this script again with your authtoken:" -ForegroundColor Yellow
    Write-Host "   .\setup-minikube-tunnel.ps1 -NgrokAuthToken YOUR_AUTH_TOKEN" -ForegroundColor White
    exit 1
}

# Configure ngrok authtoken if provided
if ($NgrokAuthToken) {
    Write-Host ""
    Write-Host "4. Configuring ngrok authtoken..."
    ngrok config add-authtoken $NgrokAuthToken 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ngrok authtoken configured" -ForegroundColor Green
    } else {
        Write-Host "   Warning: Failed to configure authtoken (it might already be set)" -ForegroundColor Yellow
    }
}

# Check if ngrok is already running
Write-Host ""
Write-Host "5. Checking for existing ngrok tunnels..."
$ngrokProcess = Get-Process -Name "ngrok" -ErrorAction SilentlyContinue
if ($ngrokProcess) {
    Write-Host "   Warning: ngrok is already running. Please stop it first:" -ForegroundColor Yellow
    Write-Host "   Stop-Process -Name ngrok -Force" -ForegroundColor White
    Write-Host ""
    $response = Read-Host "Do you want to stop existing ngrok processes? (y/n)"
    if ($response -eq "y" -or $response -eq "Y") {
        Stop-Process -Name ngrok -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Host "   Stopped existing ngrok processes" -ForegroundColor Green
    } else {
        Write-Host "   Exiting. Please stop ngrok manually and try again." -ForegroundColor Red
        exit 1
    }
}

# Start ngrok tunnel
Write-Host ""
Write-Host "6. Starting ngrok tunnel..."
Write-Host "   This will expose Minikube at $MinikubePort to the internet" -ForegroundColor Yellow
Write-Host "   Keep this window open while using GitHub Actions!" -ForegroundColor Yellow
Write-Host ""

# Start ngrok in background
$ngrokJob = Start-Job -ScriptBlock {
    param($port)
    ngrok http $port --log=stdout
} -ArgumentList $MinikubePort

Start-Sleep -Seconds 3

# Get ngrok public URL
Write-Host "7. Getting ngrok public URL..."
$maxRetries = 10
$retryCount = 0
$publicURL = $null

while ($retryCount -lt $maxRetries) {
    try {
        $ngrokAPI = Invoke-RestMethod -Uri "http://localhost:4040/api/tunnels" -ErrorAction SilentlyContinue
        if ($ngrokAPI.tunnels -and $ngrokAPI.tunnels.Count -gt 0) {
            $publicURL = $ngrokAPI.tunnels[0].public_url
            if ($publicURL) {
                break
            }
        }
    } catch {
        # ngrok API not ready yet
    }
    $retryCount++
    Start-Sleep -Seconds 1
}

if (-not $publicURL) {
    Write-Host "   Error: Could not get ngrok public URL. Check ngrok status:" -ForegroundColor Red
    Write-Host "   http://localhost:4040" -ForegroundColor Yellow
    Stop-Job $ngrokJob -ErrorAction SilentlyContinue
    Remove-Job $ngrokJob -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "   Public URL: $publicURL" -ForegroundColor Green

# Update kubeconfig
Write-Host ""
Write-Host "8. Updating kubeconfig with ngrok URL..."
$kubeconfigPath = "$env:USERPROFILE\.kube\config"
$kubeconfigBackup = "$kubeconfigPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"

# Backup original kubeconfig
Copy-Item $kubeconfigPath $kubeconfigBackup -ErrorAction SilentlyContinue
Write-Host "   Backup created: $kubeconfigBackup" -ForegroundColor Green

# Read current kubeconfig
$kubeconfigContent = Get-Content $kubeconfigPath -Raw

# Replace the server URL with ngrok URL
# Convert ngrok http URL to https
$ngrokHTTPS = $publicURL -replace '^http://', 'https://'
$kubeconfigContent = $kubeconfigContent -replace "server:\s*https://127\.0\.0\.1:\d+", "server: $ngrokHTTPS"
$kubeconfigContent = $kubeconfigContent -replace "server:\s*https://.*:58093", "server: $ngrokHTTPS"

# Save updated kubeconfig
Set-Content -Path $kubeconfigPath -Value $kubeconfigContent -NoNewline
Write-Host "   Kubeconfig updated with ngrok URL" -ForegroundColor Green

# Test connection
Write-Host ""
Write-Host "9. Testing connection to Minikube via ngrok..."
$env:KUBECONFIG = $kubeconfigPath
$testResult = kubectl cluster-info --request-timeout=10s 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   Successfully connected to Minikube via ngrok!" -ForegroundColor Green
} else {
    Write-Host "   Warning: Connection test failed. You may need to accept the ngrok certificate." -ForegroundColor Yellow
    Write-Host "   Error: $testResult" -ForegroundColor Yellow
}

# Generate base64 for GitHub Secrets
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: Keep ngrok running while using GitHub Actions!" -ForegroundColor Yellow
Write-Host ""
Write-Host "ngrok is running in the background. To view the dashboard:" -ForegroundColor Cyan
Write-Host "   http://localhost:4040" -ForegroundColor White
Write-Host ""
Write-Host "To stop ngrok:" -ForegroundColor Cyan
Write-Host "   Stop-Job $($ngrokJob.Id); Remove-Job $($ngrokJob.Id)" -ForegroundColor White
Write-Host "   Or: Stop-Process -Name ngrok -Force" -ForegroundColor White
Write-Host ""
Write-Host "To restore original kubeconfig:" -ForegroundColor Cyan
Write-Host "   Copy-Item '$kubeconfigBackup' '$kubeconfigPath' -Force" -ForegroundColor White
Write-Host ""
Write-Host "Generate base64 for GitHub Secrets:" -ForegroundColor Yellow
$base64Config = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($kubeconfigPath))
Write-Host $base64Config -ForegroundColor White
Write-Host ""
Write-Host "Copy the base64 string above and add it to GitHub Secrets as KUBECONFIG" -ForegroundColor Yellow
Write-Host ""

# Keep script running to maintain tunnel
Write-Host "Press Ctrl+C to stop ngrok and exit..." -ForegroundColor Yellow
try {
    Wait-Job $ngrokJob | Out-Null
} catch {
    Write-Host "`nStopping ngrok..." -ForegroundColor Yellow
    Stop-Job $ngrokJob -ErrorAction SilentlyContinue
    Remove-Job $ngrokJob -ErrorAction SilentlyContinue
    Stop-Process -Name ngrok -Force -ErrorAction SilentlyContinue
    
    # Restore original kubeconfig
    Write-Host "Restoring original kubeconfig..." -ForegroundColor Yellow
    Copy-Item $kubeconfigBackup $kubeconfigPath -Force -ErrorAction SilentlyContinue
    Write-Host "Done!" -ForegroundColor Green
}

