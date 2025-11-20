# Quick script to fix kubeconfig to use local Minikube instead of ngrok

Write-Host "Fixing kubeconfig to use local Minikube..." -ForegroundColor Cyan
Write-Host ""

# Check if Minikube is running
$minikubeStatus = minikube status 2>&1
$minikubeRunning = $minikubeStatus -match "host: Running"

if (-not $minikubeRunning) {
    Write-Host "Minikube is not running. Starting Minikube..." -ForegroundColor Yellow
    minikube start
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to start Minikube. Please check Docker Desktop is running." -ForegroundColor Red
        exit 1
    }
}

# Switch to minikube context
Write-Host "Switching to Minikube context..." -ForegroundColor Yellow
kubectl config use-context minikube 2>&1 | Out-Null

# Update context to ensure it's correct
Write-Host "Updating Minikube context..." -ForegroundColor Yellow
minikube update-context 2>&1 | Out-Null

# Verify connection
Write-Host "Verifying connection..." -ForegroundColor Yellow
$clusterInfo = kubectl cluster-info 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully connected to local Minikube cluster!" -ForegroundColor Green
    kubectl cluster-info | Select-Object -First 2
} else {
    Write-Host "Warning: Connection test failed. Trying force update..." -ForegroundColor Yellow
    minikube update-context --force
    kubectl cluster-info 2>&1 | Select-Object -First 3
}

Write-Host ""
Write-Host "Kubeconfig fixed! You can now run:" -ForegroundColor Green
Write-Host "  .\run-locally.ps1 -Mode k8s" -ForegroundColor White
Write-Host ""

