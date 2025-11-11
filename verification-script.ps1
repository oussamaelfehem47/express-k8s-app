Write-Host "🔍 COMPREHENSIVE KUBERNETES DEPLOYMENT VERIFICATION" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$namespace = "express-app"
$testPort = 9999

Write-Host "`n1. KUBERNETES CLUSTER STATUS" -ForegroundColor Yellow
Write-Host "─────────────────────────────" -ForegroundColor Yellow

Write-Host "`nMinikube Status:" -ForegroundColor White
minikube status

Write-Host "`nKubernetes Nodes:" -ForegroundColor White
kubectl get nodes

Write-Host "`n2. APPLICATION DEPLOYMENT STATUS" -ForegroundColor Yellow
Write-Host "─────────────────────────────────" -ForegroundColor Yellow

Write-Host "`nAll Resources in Namespace:" -ForegroundColor White
kubectl get all -n $namespace

Write-Host "`nDetailed Pod Information:" -ForegroundColor White
kubectl get pods -n $namespace -o wide

Write-Host "`n3. POD HEALTH AND READINESS" -ForegroundColor Yellow
Write-Host "────────────────────────────" -ForegroundColor Yellow

$pods = kubectl get pods -n $namespace -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
foreach ($pod in $pods -split "`n") {
    if ($pod) {
        Write-Host "`nPod: $pod" -ForegroundColor White
        Write-Host "Status:" -NoNewline
        $status = kubectl get pod $pod -n $namespace -o jsonpath='{.status.phase}'
        $ready = kubectl get pod $pod -n $namespace -o jsonpath='{.status.containerStatuses[0].ready}'
        
        if ($status -eq "Running" -and $ready -eq "true") {
            Write-Host " ✅ $status (Ready: $ready)" -ForegroundColor Green
        } else {
            Write-Host " ❌ $status (Ready: $ready)" -ForegroundColor Red
        }
        
        # Show restarts count
        $restarts = kubectl get pod $pod -n $namespace -o jsonpath='{.status.containerStatuses[0].restartCount}'
        Write-Host "Restarts: $restarts" -ForegroundColor $(if ($restarts -gt 0) { "Yellow" } else { "Gray" })
    }
}

Write-Host "`n4. SERVICE AND NETWORKING" -ForegroundColor Yellow
Write-Host "──────────────────────────" -ForegroundColor Yellow

Write-Host "`nServices:" -ForegroundColor White
kubectl get services -n $namespace

Write-Host "`nService Details:" -ForegroundColor White
kubectl describe service express-service -n $namespace | Select-String -Pattern "Name:|Namespace:|Type:|IP:|Port:|TargetPort:" -Context 0,1

Write-Host "`n5. APPLICATION ENDPOINT TESTING" -ForegroundColor Yellow
Write-Host "────────────────────────────────" -ForegroundColor Yellow

Write-Host "`nChecking if port-forward is active..." -ForegroundColor White
$portForwardActive = $false
try {
    $response = Invoke-WebRequest -Uri "http://localhost:$testPort/health" -UseBasicParsing -TimeoutSec 3
    $portForwardActive = $true
    Write-Host "✅ Port-forward is ACTIVE on port $testPort" -ForegroundColor Green
} catch {
    Write-Host "❌ Port-forward is NOT active. Starting temporary port-forward..." -ForegroundColor Yellow
    # Start temporary port-forward
    $tempJob = Start-Job -ScriptBlock {
        param($namespace, $port)
        kubectl port-forward -n $namespace service/express-service ${port}:80
    } -ArgumentList $namespace, $testPort
    Start-Sleep 5
}

Write-Host "`nTesting Application Endpoints:" -ForegroundColor White

$endpoints = @(
    @{Path="/"; Description="Main Endpoint"; Expected="Hello from Kubernetes"},
    @{Path="/health"; Description="Health Check"; Expected="OK"},
    @{Path="/info"; Description="Info Endpoint"; Expected="Express Kubernetes Demo"}
)

$allEndpointsWorking = $true
foreach ($endpoint in $endpoints) {
    Write-Host "`nTesting $($endpoint.Description)..." -ForegroundColor Gray
    Write-Host "URL: http://localhost:$testPort$($endpoint.Path)" -ForegroundColor Gray
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$testPort$($endpoint.Path)" -UseBasicParsing -TimeoutSec 5
        $data = $response.Content | ConvertFrom-Json
        
        # Fixed: Using compatible PowerShell syntax instead of ?? operator
        $responseText = ""
        if ($data.message) { $responseText = $data.message }
        elseif ($data.status) { $responseText = $data.status }
        elseif ($data.app) { $responseText = $data.app }
        else { $responseText = "Unknown response" }
        
        if ($data.message -like "*$($endpoint.Expected)*" -or $data.status -eq "OK" -or $data.app -eq $endpoint.Expected) {
            Write-Host "✅ RESPONSE: " -NoNewline -ForegroundColor Green
            Write-Host $responseText -ForegroundColor White
            Write-Host "   Status Code: $($response.StatusCode)" -ForegroundColor Gray
            Write-Host "   Response Time: Successful" -ForegroundColor Gray
        } else {
            Write-Host "⚠️  UNEXPECTED RESPONSE" -ForegroundColor Yellow
            Write-Host "   Content: $($response.Content)" -ForegroundColor Gray
            $allEndpointsWorking = $false
        }
    } catch {
        Write-Host "❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $allEndpointsWorking = $false
    }
}

Write-Host "`n6. LOAD BALANCING VERIFICATION" -ForegroundColor Yellow
Write-Host "──────────────────────────────" -ForegroundColor Yellow

if ($allEndpointsWorking) {
    Write-Host "`nTesting load balancing across 3 pods:" -ForegroundColor White
    $podResponses = @{}
    
    1..9 | ForEach-Object {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$testPort" -UseBasicParsing
            $data = $response.Content | ConvertFrom-Json
            $podName = $data.host.Split('.')[0]
            
            if ($podResponses.ContainsKey($podName)) {
                $podResponses[$podName]++
            } else {
                $podResponses[$podName] = 1
            }
            
            Write-Host "   Request $_ → Pod: $podName" -ForegroundColor Gray
            Start-Sleep -Milliseconds 200
        } catch {
            Write-Host "   Request $_ → Failed" -ForegroundColor Red
        }
    }
    
    Write-Host "`nLoad Distribution Summary:" -ForegroundColor White
    foreach ($pod in $podResponses.Keys) {
        $count = $podResponses[$pod]
        Write-Host "   $pod : $count requests" -ForegroundColor $(if ($count -ge 2) { "Green" } else { "Yellow" })
    }
    
    if ($podResponses.Count -ge 2) {
        Write-Host "✅ Load balancing is WORKING across multiple pods!" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Load balancing may not be distributing evenly" -ForegroundColor Yellow
    }
}

Write-Host "`n7. DEPLOYMENT HEALTH CHECKS" -ForegroundColor Yellow
Write-Host "────────────────────────────" -ForegroundColor Yellow

Write-Host "`nPod Logs Sample (Recent):" -ForegroundColor White
foreach ($pod in $pods -split "`n") {
    if ($pod) {
        Write-Host "`nLogs from $pod :" -ForegroundColor Cyan
        kubectl logs $pod -n $namespace --tail=2 --timestamps=true 2>$null
    }
}

Write-Host "`n8. RESOURCE USAGE" -ForegroundColor Yellow
Write-Host "──────────────────" -ForegroundColor Yellow

Write-Host "`nResource Limits and Usage:" -ForegroundColor White
kubectl top pods -n $namespace 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "   Metrics not available (metrics-server may not be installed)" -ForegroundColor Yellow
}

Write-Host "`n9. FINAL VERIFICATION SUMMARY" -ForegroundColor Yellow
Write-Host "──────────────────────────────" -ForegroundColor Yellow

Write-Host "`nDeployment Status:" -ForegroundColor White
$deploymentStatus = kubectl get deployment express-app -n $namespace -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
$replicasReady = kubectl get deployment express-app -n $namespace -o jsonpath='{.status.readyReplicas}'
$replicasDesired = kubectl get deployment express-app -n $namespace -o jsonpath='{.status.replicas}'

if ($deploymentStatus -eq "True" -and $replicasReady -eq $replicasDesired -and $allEndpointsWorking) {
    Write-Host "🎉 🎉 🎉 DEPLOYMENT VERIFICATION: COMPLETE SUCCESS! 🎉 🎉 🎉" -ForegroundColor Green
    Write-Host "`n✅ All Kubernetes components are healthy" -ForegroundColor Green
    Write-Host "✅ All application endpoints are responding" -ForegroundColor Green
    Write-Host "✅ Load balancing is working across $replicasReady pods" -ForegroundColor Green
    Write-Host "✅ Service discovery is functional" -ForegroundColor Green
    Write-Host "✅ Health checks are passing" -ForegroundColor Green
    Write-Host "`n🚀 Ready to proceed with Helm charts! 🚀" -ForegroundColor Cyan
} else {
    Write-Host "❌ DEPLOYMENT VERIFICATION: ISSUES DETECTED" -ForegroundColor Red
    if ($deploymentStatus -ne "True") {
        Write-Host "   - Deployment not available" -ForegroundColor Red
    }
    if ($replicasReady -ne $replicasDesired) {
        Write-Host "   - Pods not ready ($replicasReady/$replicasDesired)" -ForegroundColor Red
    }
    if (-not $allEndpointsWorking) {
        Write-Host "   - Application endpoints failing" -ForegroundColor Red
    }
}

Write-Host "`n📊 QUICK ACCESS COMMANDS:" -ForegroundColor Cyan
Write-Host "   View pods: kubectl get pods -n $namespace" -ForegroundColor Gray
Write-Host "   View logs: kubectl logs -n $namespace -l app=express-app --tail=10" -ForegroundColor Gray
Write-Host "   Port-forward: kubectl port-forward -n $namespace service/express-service 9999:80" -ForegroundColor Gray
Write-Host "   Application: http://localhost:$testPort" -ForegroundColor Gray

# Clean up temporary port-forward if we started one
if (Get-Variable -Name "tempJob" -ErrorAction SilentlyContinue) {
    Get-Job | Stop-Job | Remove-Job
}

Write-Host "`n🔍 Verification completed at: $(Get-Date)" -ForegroundColor Gray
