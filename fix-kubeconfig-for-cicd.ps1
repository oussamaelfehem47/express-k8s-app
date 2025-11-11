# Script to fix kubeconfig for CI/CD by embedding certificates as base64
# This converts file paths to embedded certificate data

param(
    [string]$KubeconfigPath = "$env:USERPROFILE\.kube\config",
    [string]$OutputPath = "$env:USERPROFILE\.kube\config.cicd"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Fix Kubeconfig for CI/CD" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if kubeconfig exists
if (-not (Test-Path $KubeconfigPath)) {
    Write-Host "Error: Kubeconfig not found at: $KubeconfigPath" -ForegroundColor Red
    exit 1
}

Write-Host "Reading kubeconfig from: $KubeconfigPath" -ForegroundColor Green

# Read kubeconfig as YAML
$kubeconfigContent = Get-Content $KubeconfigPath -Raw

# Parse YAML (simple parsing for our needs)
$kubeconfig = [System.Collections.ArrayList]@()
$lines = $kubeconfigContent -split "`n"

# Track current context
$currentUser = $null
$currentCluster = $null
$inUser = $false
$inCluster = $false

# Process each line
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $trimmed = $line.Trim()
    
    # Detect user section
    if ($trimmed -match "^- name:\s*(.+)$") {
        $currentUser = $matches[1].Trim()
        $inUser = $false
        $kubeconfig.Add($line) | Out-Null
    }
    elseif ($trimmed -match "^users:") {
        $kubeconfig.Add($line) | Out-Null
    }
    elseif ($trimmed -match "^  user:") {
        $inUser = $true
        $kubeconfig.Add($line) | Out-Null
    }
    elseif ($inUser -and $trimmed -match "client-certificate:\s*(.+)") {
        $certPath = $matches[1].Trim()
        Write-Host "Found client-certificate path: $certPath" -ForegroundColor Yellow
        
        if (Test-Path $certPath) {
            $certData = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($certPath))
            $kubeconfig.Add("    client-certificate-data: $certData") | Out-Null
            Write-Host "  Embedded client-certificate as base64" -ForegroundColor Green
        } else {
            Write-Host "  Warning: Certificate file not found: $certPath" -ForegroundColor Yellow
            $kubeconfig.Add($line) | Out-Null
        }
    }
    elseif ($inUser -and $trimmed -match "client-key:\s*(.+)") {
        $keyPath = $matches[1].Trim()
        Write-Host "Found client-key path: $keyPath" -ForegroundColor Yellow
        
        if (Test-Path $keyPath) {
            $keyData = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($keyPath))
            $kubeconfig.Add("    client-key-data: $keyData") | Out-Null
            Write-Host "  Embedded client-key as base64" -ForegroundColor Green
        } else {
            Write-Host "  Warning: Key file not found: $keyPath" -ForegroundColor Yellow
            $kubeconfig.Add($line) | Out-Null
        }
    }
    elseif ($inUser -and ($trimmed -match "client-certificate:" -or $trimmed -match "client-key:")) {
        # Skip the old line, we already added the embedded version
        continue
    }
    elseif ($trimmed -match "^clusters:") {
        $inUser = $false
        $kubeconfig.Add($line) | Out-Null
    }
    elseif ($trimmed -match "^  cluster:") {
        $inCluster = $true
        $kubeconfig.Add($line) | Out-Null
    }
    elseif ($inCluster -and $trimmed -match "certificate-authority:\s*(.+)") {
        $caPath = $matches[1].Trim()
        Write-Host "Found certificate-authority path: $caPath" -ForegroundColor Yellow
        
        if (Test-Path $caPath) {
            $caData = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($caPath))
            $kubeconfig.Add("    certificate-authority-data: $caData") | Out-Null
            Write-Host "  Embedded certificate-authority as base64" -ForegroundColor Green
        } else {
            Write-Host "  Warning: CA file not found: $caPath" -ForegroundColor Yellow
            $kubeconfig.Add($line) | Out-Null
        }
    }
    elseif ($inCluster -and $trimmed -match "certificate-authority:") {
        # Skip the old line, we already added the embedded version
        continue
    }
    elseif ($trimmed -match "^\s") {
        # Indented line - might be ending a section
        if (-not ($trimmed -match "certificate-authority:" -or $trimmed -match "client-certificate:" -or $trimmed -match "client-key:")) {
            $kubeconfig.Add($line) | Out-Null
        }
        if ($trimmed -match "^  [a-z]") {
            $inCluster = $false
        }
    }
    else {
        $inUser = $false
        $inCluster = $false
        $kubeconfig.Add($line) | Out-Null
    }
}

# Better approach: Use a proper YAML parser or regex replacement
Write-Host ""
Write-Host "Using regex-based replacement method..." -ForegroundColor Cyan

# Read original content
$originalContent = Get-Content $KubeconfigPath -Raw
$fixedContent = $originalContent

# Find and replace client-certificate
$certMatches = [regex]::Matches($originalContent, "client-certificate:\s*(.+?)(\r?\n)")
foreach ($match in $certMatches) {
    $certPath = $match.Groups[1].Value.Trim()
    Write-Host "Processing client-certificate: $certPath" -ForegroundColor Yellow
    
    if (Test-Path $certPath) {
        $certData = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($certPath))
        $replacement = "client-certificate-data: $certData" + $match.Groups[2].Value
        $fixedContent = $fixedContent -replace [regex]::Escape($match.Value), $replacement
        Write-Host "  Embedded as base64" -ForegroundColor Green
    } else {
        Write-Host "  Warning: File not found: $certPath" -ForegroundColor Yellow
    }
}

# Find and replace client-key
$keyMatches = [regex]::Matches($fixedContent, "client-key:\s*(.+?)(\r?\n)")
foreach ($match in $keyMatches) {
    $keyPath = $match.Groups[1].Value.Trim()
    Write-Host "Processing client-key: $keyPath" -ForegroundColor Yellow
    
    if (Test-Path $keyPath) {
        $keyData = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($keyPath))
        $replacement = "client-key-data: $keyData" + $match.Groups[2].Value
        $fixedContent = $fixedContent -replace [regex]::Escape($match.Value), $replacement
        Write-Host "  Embedded as base64" -ForegroundColor Green
    } else {
        Write-Host "  Warning: File not found: $keyPath" -ForegroundColor Yellow
    }
}

# For ngrok, we should skip TLS verification instead of using certificate-authority
# Check if this is an ngrok URL
if ($fixedContent -match "server:\s*https://.*\.ngrok") {
    Write-Host "Detected ngrok URL - configuring to skip TLS verification..." -ForegroundColor Yellow
    # Remove certificate-authority
    $fixedContent = $fixedContent -replace "certificate-authority:\s*(.+?)(\r?\n)", ""
    $fixedContent = $fixedContent -replace "certificate-authority-data:\s*(.+?)(\r?\n)", ""
    
    # Add insecure-skip-tls-verify
    $serverMatches = [regex]::Matches($fixedContent, "server:\s*(https://.*\.ngrok[^\r\n]+)(\r?\n)")
    foreach ($match in $serverMatches) {
        $serverURL = $match.Groups[1].Value
        if ($fixedContent -notmatch "insecure-skip-tls-verify:\s*true") {
            $replacement = "server: $serverURL" + $match.Groups[2].Value + "    insecure-skip-tls-verify: true" + $match.Groups[2].Value
            $fixedContent = $fixedContent -replace [regex]::Escape($match.Value), $replacement
            Write-Host "  Added insecure-skip-tls-verify: true" -ForegroundColor Green
        }
    }
} else {
    # For non-ngrok, embed certificate-authority normally
    $caMatches = [regex]::Matches($fixedContent, "certificate-authority:\s*(.+?)(\r?\n)")
    foreach ($match in $caMatches) {
        $caPath = $match.Groups[1].Value.Trim()
        Write-Host "Processing certificate-authority: $caPath" -ForegroundColor Yellow
        
        if (Test-Path $caPath) {
            $caData = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($caPath))
            $replacement = "certificate-authority-data: $caData" + $match.Groups[2].Value
            $fixedContent = $fixedContent -replace [regex]::Escape($match.Value), $replacement
            Write-Host "  Embedded as base64" -ForegroundColor Green
        } else {
            Write-Host "  Warning: File not found: $caPath" -ForegroundColor Yellow
        }
    }
}

# Save fixed kubeconfig
Set-Content -Path $OutputPath -Value $fixedContent -NoNewline
Write-Host ""
Write-Host "Fixed kubeconfig saved to: $OutputPath" -ForegroundColor Green

# Verify the fixed kubeconfig
Write-Host ""
Write-Host "Verifying fixed kubeconfig..." -ForegroundColor Cyan
$env:KUBECONFIG = $OutputPath
$testResult = kubectl config view --raw 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Kubeconfig is valid!" -ForegroundColor Green
} else {
    Write-Host "Warning: Kubeconfig validation failed" -ForegroundColor Yellow
    Write-Host $testResult
}

# Generate base64 for GitHub Secrets
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Base64 for GitHub Secrets" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
$base64Config = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($OutputPath))
Write-Host $base64Config -ForegroundColor White
Write-Host ""
Write-Host "Copy the base64 string above and update GitHub Secret KUBECONFIG" -ForegroundColor Yellow
Write-Host ""

