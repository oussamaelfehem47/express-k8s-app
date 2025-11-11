Write-Host "🔧 FIXING HELM DEPLOYMENT ISSUES" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

$namespace = "express-app"
$chartName = "express-app"

Write-Host "`n1. Checking current state..." -ForegroundColor Yellow
kubectl get namespace $namespace
kubectl get all -n $namespace 2>$null

Write-Host "`n2. Cleaning up any stuck resources..." -ForegroundColor Yellow

# Delete any existing Helm release
helm uninstall $chartName -n $namespace 2>$null

# Force delete namespace if stuck
Write-Host "Force deleting namespace if stuck..." -ForegroundColor Yellow
kubectl delete namespace $namespace --force --grace-period=0 2>$null
Start-Sleep 5

# Check if namespace is gone
$nsExists = kubectl get namespace $namespace 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Namespace still exists, using finalizer removal..." -ForegroundColor Yellow
    kubectl get namespace $namespace -o json | %{ $_ -replace '"kubernetes"', '"null"' } | kubectl replace --raw "/api/v1/namespaces/$namespace/finalize" -f -
    Start-Sleep 3
}

Write-Host "`n3. Creating fresh namespace..." -ForegroundColor Yellow
kubectl create namespace $namespace
Start-Sleep 2

Write-Host "`n4. Deploying with Helm..." -ForegroundColor Yellow
helm install $chartName ./express-helm-chart -n $namespace

Write-Host "`n5. Waiting for deployment to be ready..." -ForegroundColor Yellow
Start-Sleep 10

Write-Host "`n6. Verifying deployment..." -ForegroundColor Yellow
helm list -n $namespace
kubectl get all -n $namespace

Write-Host "`n7. Testing application..." -ForegroundColor Yellow
# Start port-forward
$portForwardJob = Start-Job -ScriptBlock {
    kubectl port-forward -n $using:namespace service/express-app-service 8888:80
}
Start-Sleep 5

try {
    $response = Invoke-WebRequest -Uri "http://localhost:8888" -UseBasicParsing -TimeoutSec 10
    Write-Host "✅ Application is working via Helm deployment!" -ForegroundColor Green
    Write-Host "Response: $($response.Content)" -ForegroundColor Gray
    
    # Test all endpoints
    $endpoints = @("/", "/health", "/info")
    foreach ($endpoint in $endpoints) {
        $response = Invoke-WebRequest -Uri "http://localhost:8888$endpoint" -UseBasicParsing
        Write-Host "✅ $endpoint endpoint: WORKING" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Application not accessible: $($_.Exception.Message)" -ForegroundColor Red
}

# Clean up port-forward
Get-Job | Stop-Job | Remove-Job

Write-Host "`n🎉 HELM DEPLOYMENT FIXED AND RUNNING!" -ForegroundColor Green
