# Quick script to update kubeconfig with current ngrok URL
# Use this if ngrok is already running and you just need to update the kubeconfig

Write-Host "Updating kubeconfig with current ngrok URL..." -ForegroundColor Cyan
Write-Host ""

# Check if ngrok is running
$ngrokProcess = Get-Process -Name "ngrok" -ErrorAction SilentlyContinue
if (-not $ngrokProcess) {
    Write-Host "Error: ngrok is not running!" -ForegroundColor Red
    Write-Host "Please start ngrok first:" -ForegroundColor Yellow
    Write-Host "  ngrok http 58093" -ForegroundColor White
    Write-Host "Or run: .\setup-minikube-tunnel.ps1" -ForegroundColor White
    exit 1
}

# Get ngrok public URL
Write-Host "Getting ngrok public URL..."
$maxRetries = 5
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
    Write-Host "Error: Could not get ngrok public URL from http://localhost:4040" -ForegroundColor Red
    Write-Host "Make sure ngrok is running and accessible." -ForegroundColor Yellow
    exit 1
}

# Convert to HTTPS
$ngrokHTTPS = $publicURL -replace '^http://', 'https://'
Write-Host "Public URL: $ngrokHTTPS" -ForegroundColor Green

# Update kubeconfig
$kubeconfigPath = "$env:USERPROFILE\.kube\config"
if (-not (Test-Path $kubeconfigPath)) {
    Write-Host "Error: Kubeconfig not found at $kubeconfigPath" -ForegroundColor Red
    exit 1
}

# Backup
$timestamp = Get-Date -Format 'yyyyMMddHHmmss'
$backupPath = "$kubeconfigPath.backup.$timestamp"
Copy-Item $kubeconfigPath $backupPath -ErrorAction SilentlyContinue
Write-Host "Backup created: $backupPath" -ForegroundColor Green

# Read and update
$kubeconfigContent = Get-Content $kubeconfigPath -Raw
$kubeconfigContent = $kubeconfigContent -replace "server:\s*https://127\.0\.0\.1:\d+", "server: $ngrokHTTPS"
$kubeconfigContent = $kubeconfigContent -replace "server:\s*https://.*:58093", "server: $ngrokHTTPS"
$kubeconfigContent = $kubeconfigContent -replace "server:\s*https://.*\.ngrok\.io", "server: $ngrokHTTPS"
$kubeconfigContent = $kubeconfigContent -replace "server:\s*https://.*\.ngrok-free\.app", "server: $ngrokHTTPS"

# Skip TLS verification for ngrok (ngrok uses self-signed certificates)
Write-Host "Configuring to skip TLS verification for ngrok..." -ForegroundColor Yellow
# Remove certificate-authority if present
$kubeconfigContent = $kubeconfigContent -replace "certificate-authority:\s*(.+?)(\r?\n)", ""
$kubeconfigContent = $kubeconfigContent -replace "certificate-authority-data:\s*(.+?)(\r?\n)", ""

# Add insecure-skip-tls-verify after server line
if ($kubeconfigContent -notmatch "insecure-skip-tls-verify:\s*true") {
    $kubeconfigContent = $kubeconfigContent -replace "(server:\s*$([regex]::Escape($ngrokHTTPS)))(\r?\n)", "`$1`$2    insecure-skip-tls-verify: true`$2"
    Write-Host "  Added insecure-skip-tls-verify: true" -ForegroundColor Green
}

# Embed certificates as base64 (fix for CI/CD)
Write-Host "Embedding certificates as base64 for CI/CD compatibility..." -ForegroundColor Yellow

# Find and replace client-certificate
$certMatches = [regex]::Matches($kubeconfigContent, "client-certificate:\s*(.+?)(\r?\n)")
foreach ($match in $certMatches) {
    $certPath = $match.Groups[1].Value.Trim()
    if (Test-Path $certPath) {
        $certData = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($certPath))
        $replacement = "client-certificate-data: $certData" + $match.Groups[2].Value
        $kubeconfigContent = $kubeconfigContent -replace [regex]::Escape($match.Value), $replacement
        Write-Host "  Embedded client-certificate" -ForegroundColor Green
    }
}

# Find and replace client-key
$keyMatches = [regex]::Matches($kubeconfigContent, "client-key:\s*(.+?)(\r?\n)")
foreach ($match in $keyMatches) {
    $keyPath = $match.Groups[1].Value.Trim()
    if (Test-Path $keyPath) {
        $keyData = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($keyPath))
        $replacement = "client-key-data: $keyData" + $match.Groups[2].Value
        $kubeconfigContent = $kubeconfigContent -replace [regex]::Escape($match.Value), $replacement
        Write-Host "  Embedded client-key" -ForegroundColor Green
    }
}

# Note: We skip certificate-authority for ngrok since we're using insecure-skip-tls-verify
# This is safe for testing with ngrok's self-signed certificates

Set-Content -Path $kubeconfigPath -Value $kubeconfigContent -NoNewline
Write-Host "Kubeconfig updated!" -ForegroundColor Green

# Test connection
Write-Host ""
Write-Host "Testing connection..."
$env:KUBECONFIG = $kubeconfigPath
$testResult = kubectl cluster-info --request-timeout=10s 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Connection successful!" -ForegroundColor Green
} else {
    Write-Host "Warning: Connection test failed" -ForegroundColor Yellow
}

# Generate base64
Write-Host ""
Write-Host "Base64 for GitHub Secrets:" -ForegroundColor Cyan
$base64Config = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($kubeconfigPath))
Write-Host $base64Config -ForegroundColor White
Write-Host ""
Write-Host "Copy the base64 string above and update GitHub Secret KUBECONFIG" -ForegroundColor Yellow

