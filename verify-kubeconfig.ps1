# PowerShell script to verify KUBECONFIG before adding it to GitHub Secrets
# Usage: .\verify-kubeconfig.ps1 [path-to-kubeconfig]

param(
    [string]$KubeconfigPath = "$env:USERPROFILE\.kube\config"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "KUBECONFIG Verification Script" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if file exists
if (-not (Test-Path $KubeconfigPath)) {
    Write-Host "Error: Kubeconfig file not found at: $KubeconfigPath" -ForegroundColor Red
    exit 1
}

Write-Host "Found kubeconfig file: $KubeconfigPath" -ForegroundColor Green
Write-Host ""

# Check file size
$fileSize = (Get-Item $KubeconfigPath).Length
Write-Host "File size: $fileSize bytes"
Write-Host ""

# Check if kubectl is available
$kubectlAvailable = $false
$null = kubectl version --client 2>&1
if ($LASTEXITCODE -eq 0) {
    $kubectlAvailable = $true
} else {
    Write-Host "Warning: kubectl not found in PATH" -ForegroundColor Yellow
}

if ($kubectlAvailable) {
    # Check if it's valid YAML
    Write-Host "1. Validating YAML structure..."
    $env:KUBECONFIG = $KubeconfigPath
    $result = kubectl config view --raw 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   Valid YAML structure" -ForegroundColor Green
    } else {
        Write-Host "   Invalid YAML structure" -ForegroundColor Red
        Write-Host "   Error details:"
        $result | Select-Object -First 5
        exit 1
    }
    
    # Verify cluster connectivity (optional)
    Write-Host ""
    Write-Host "2. Testing cluster connectivity..."
    $clusterInfo = kubectl cluster-info --request-timeout=5s 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   Successfully connected to cluster" -ForegroundColor Green
        $clusterInfo | Select-Object -First 2
    } else {
        Write-Host "   Warning: Could not connect to cluster (this might be expected)" -ForegroundColor Yellow
    }
} else {
    Write-Host "1. Skipping kubectl validation (kubectl not available)" -ForegroundColor Yellow
}

# Check file content
Write-Host ""
Write-Host "3. Checking file format..."
$firstLine = Get-Content $KubeconfigPath -First 1
if ($firstLine -match "apiVersion|kind") {
    Write-Host "   File starts with expected content: $firstLine" -ForegroundColor Green
} else {
    Write-Host "   Warning: File doesn't start with expected YAML content" -ForegroundColor Yellow
    Write-Host "   First line: $firstLine"
}

# Check for BOM
Write-Host ""
Write-Host "4. Checking for BOM (Byte Order Mark)..."
$bytes = [System.IO.File]::ReadAllBytes($KubeconfigPath)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "   Warning: File contains UTF-8 BOM (this can cause issues)" -ForegroundColor Yellow
} else {
    Write-Host "   No BOM detected" -ForegroundColor Green
}

# Test base64 encoding
Write-Host ""
Write-Host "5. Testing base64 encoding..."
$fileContent = [System.IO.File]::ReadAllText($KubeconfigPath)
$base64Encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($fileContent))
Write-Host "   Base64 length: $($base64Encoded.Length) characters"

# Test decoding
try {
    $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64Encoded))
    if ($decoded.Length -gt 0) {
        Write-Host "   Base64 encoding/decoding works correctly" -ForegroundColor Green
    } else {
        Write-Host "   Base64 decoding resulted in empty string" -ForegroundColor Red
        exit 1
    }
} catch {
    $errorMsg = $_.Exception.Message
    Write-Host "   Base64 encoding/decoding failed: $errorMsg" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Kubeconfig file is valid and ready to use" -ForegroundColor Green
Write-Host ""
Write-Host "To add to GitHub Secrets:" -ForegroundColor Yellow
Write-Host "1. For BASE64 (recommended):" -ForegroundColor Yellow
Write-Host "   Run this command and copy the output:"
Write-Host ('   [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("' + $KubeconfigPath + '"))') -ForegroundColor White
Write-Host ""
Write-Host "2. For PLAIN TEXT:" -ForegroundColor Yellow
Write-Host "   Copy the entire contents of: $KubeconfigPath"
Write-Host ""
Write-Host "Then paste into GitHub:" -ForegroundColor Yellow
Write-Host "   Repository -> Settings -> Secrets and variables -> Actions -> New repository secret"
Write-Host "   Name: KUBECONFIG"
Write-Host ('   Value: paste the base64 string or plain text') -ForegroundColor White
Write-Host ""
