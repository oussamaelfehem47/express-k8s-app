param(
    [ValidateSet('node','docker','k8s')]
    [string]$Mode = 'node',
    [int]$Port = 8081  # 👈 NEW: Make port configurable
)

Write-Host '=========================================' -ForegroundColor Cyan
Write-Host ("Express.js Project Launcher ({0} mode)" -f $Mode) -ForegroundColor Cyan
Write-Host '=========================================' -ForegroundColor Cyan

# Function to find available port
function Get-AvailablePort {
    param([int]$StartPort = 8080)
    
    $port = $StartPort
    while ($port -lt 65535) {
        $result = netstat -ano | findstr ":$port "
        if (-not $result) {
            return $port
        }
        $port++
    }
    return $StartPort + 1000  # Fallback
}

switch ($Mode) {
    'node' {
        Write-Host "`n1. Installing dependencies..." -ForegroundColor Yellow
        if (-not (Test-Path 'node_modules')) {
            npm install
        } else {
            Write-Host '   node_modules already exists; skipping npm install' -ForegroundColor Gray
        }

        Write-Host "`n2. Starting application with npm start..." -ForegroundColor Yellow
        Write-Host '   Press Ctrl+C to stop.' -ForegroundColor Gray
        npm start
    }

    'docker' {
        $imageName = 'express-k8s-app:local'
        Write-Host "`n1. Building Docker image..." -ForegroundColor Yellow
        docker build -t $imageName .

        Write-Host "`n2. Running container on port 3000..." -ForegroundColor Yellow
        Write-Host '   Press Ctrl+C to stop.' -ForegroundColor Gray
        docker run --rm -p 3000:3000 $imageName
    }

    'k8s' {
        $namespace = 'express-app'
        
        Write-Host "`n1. Checking Minikube status..." -ForegroundColor Yellow
        $minikubeStatus = minikube status 2>&1
        $minikubeRunning = $minikubeStatus -match "host: Running" -and $minikubeStatus -match "kubelet: Running"
        
        if (-not $minikubeRunning) {
            Write-Host "   Minikube is not running. Starting Minikube..." -ForegroundColor Yellow
            minikube start
            if ($LASTEXITCODE -ne 0) {
                Write-Host "   Error: Failed to start Minikube. Please check Docker Desktop is running." -ForegroundColor Red
                exit 1
            }
            Write-Host "   Minikube started successfully!" -ForegroundColor Green
        } else {
            Write-Host "   Minikube is already running" -ForegroundColor Green
        }
        
        Write-Host "`n2. Fixing kubeconfig to use local Minikube..." -ForegroundColor Yellow
        # Switch to minikube context and update it
        kubectl config use-context minikube 2>&1 | Out-Null
        minikube update-context 2>&1 | Out-Null
        
        # Verify connection
        $clusterInfo = kubectl cluster-info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   Warning: Could not connect to cluster. Trying to fix..." -ForegroundColor Yellow
            minikube update-context --force
        } else {
            Write-Host "   Successfully connected to local Minikube cluster" -ForegroundColor Green
        }

        Write-Host "`n3. Deploying with Helm..." -ForegroundColor Yellow
        helm upgrade --install express-app ./express-helm-chart `
            --namespace $namespace `
            --create-namespace
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   Error: Helm deployment failed" -ForegroundColor Red
            exit 1
        }

        Write-Host "`n4. Waiting for pods to be ready..." -ForegroundColor Yellow
        kubectl rollout status deployment/express-app -n $namespace --timeout=180s
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   Warning: Deployment may not be fully ready. Checking pods..." -ForegroundColor Yellow
            kubectl get pods -n $namespace
        } else {
            Write-Host "   All pods are ready!" -ForegroundColor Green
        }

        # 👇 UPDATED: Smart port selection
        Write-Host "`n5. Finding available port..." -ForegroundColor Yellow
        $selectedPort = Get-AvailablePort -StartPort $Port
        if ($selectedPort -ne $Port) {
            Write-Host "   Port $Port is busy, using port $selectedPort instead" -ForegroundColor Yellow
        }
        
        Write-Host "   Starting port-forward (service/express-app-service ${selectedPort}:80)..." -ForegroundColor Yellow
        Write-Host "   Visit http://localhost:${selectedPort} (Ctrl+C to stop)" -ForegroundColor Green
        Write-Host "   Endpoints: /, /health, /info" -ForegroundColor Gray
        kubectl port-forward -n $namespace service/express-app-service ${selectedPort}:80
    }
}