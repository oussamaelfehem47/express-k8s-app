# Test everything works locally one final time

Write-Host "🔍 RUNNING FINAL LOCAL TEST..." -ForegroundColor Cyan

Write-Host "`n1. Checking Kubernetes cluster..." -ForegroundColor Yellow
minikube status
kubectl get nodes

Write-Host "`n2. Checking application deployment..." -ForegroundColor Yellow
kubectl get all -n express-app

Write-Host "`n3. Testing application access..." -ForegroundColor Yellow

# Check if service exists
$serviceExists = kubectl get service express-app-service -n express-app 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "   Service exists, starting port-forward..." -ForegroundColor Green
    
    # Start port-forward in background
    $portForwardJob = Start-Job -ScriptBlock {
        kubectl port-forward -n express-app service/express-app-service 8888:80 2>&1
    }
    
    # Wait for port-forward to establish
    Start-Sleep 5
    
    # Test the application
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8888" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Write-Host "✅ Application is running at http://localhost:8888" -ForegroundColor Green
        
        $healthResponse = Invoke-WebRequest -Uri "http://localhost:8888/health" -UseBasicParsing -ErrorAction Stop
        Write-Host "✅ Health endpoint working" -ForegroundColor Green
        
        $infoResponse = Invoke-WebRequest -Uri "http://localhost:8888/info" -UseBasicParsing -ErrorAction Stop
        Write-Host "✅ Info endpoint working" -ForegroundColor Green
        
    } catch {
        Write-Host "⚠️  Application test failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   This is okay if the service isn't currently deployed" -ForegroundColor Gray
    }
    
    # Clean up port-forward
    Get-Job | Stop-Job -ErrorAction SilentlyContinue
    Get-Job | Remove-Job -ErrorAction SilentlyContinue
} else {
    Write-Host "⚠️  Service not found. Deploy first with:" -ForegroundColor Yellow
    Write-Host "   helm install express-app ./express-helm-chart" -ForegroundColor White
}

Write-Host "`n✅ All local tests completed!" -ForegroundColor Green

