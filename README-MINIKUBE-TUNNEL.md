# Minikube Tunnel Setup for GitHub Actions

This guide explains how to expose your local Minikube cluster to GitHub Actions using ngrok.

## ⚠️ Important Notes

- **This is for testing only** - Not recommended for production
- **Keep ngrok running** - The tunnel must be active when GitHub Actions runs
- **ngrok free tier limitations** - Free tier has session limits and URL changes on restart
- **Security** - Your local cluster will be exposed to the internet (use with caution)

## Prerequisites

1. **Minikube** - Must be running
2. **ngrok** - Download from https://ngrok.com/download
3. **ngrok account** - Sign up at https://dashboard.ngrok.com/signup (free)

## Step-by-Step Setup

### 1. Install ngrok

1. Download ngrok from https://ngrok.com/download
2. Extract the executable
3. Add to PATH or run from the extracted folder

### 2. Get Your ngrok Authtoken

1. Sign up at https://dashboard.ngrok.com/signup
2. Get your authtoken from https://dashboard.ngrok.com/get-started/your-authtoken
3. Save it for the next step

### 3. Start Minikube

```powershell
minikube start
```

Verify it's running:
```powershell
minikube status
kubectl cluster-info
```

### 4. Run the Tunnel Setup Script

```powershell
.\setup-minikube-tunnel.ps1 -NgrokAuthToken YOUR_AUTH_TOKEN
```

Or if ngrok is already configured:
```powershell
.\setup-minikube-tunnel.ps1
```

### 5. What the Script Does

1. ✅ Checks Minikube is running
2. ✅ Verifies ngrok is installed
3. ✅ Configures ngrok authtoken (if provided)
4. ✅ Starts ngrok tunnel to Minikube API server
5. ✅ Gets the public ngrok URL
6. ✅ Updates your kubeconfig to use the ngrok URL
7. ✅ Tests the connection
8. ✅ Generates base64-encoded kubeconfig for GitHub Secrets

### 6. Add to GitHub Secrets

1. Copy the base64 string from the script output
2. Go to your GitHub repository
3. Navigate to: **Settings → Secrets and variables → Actions**
4. Click **"New repository secret"**
5. Name: `KUBECONFIG`
6. Value: Paste the base64 string
7. Click **"Add secret"**

### 7. Keep ngrok Running

**IMPORTANT:** You must keep ngrok running while GitHub Actions workflows execute!

- The script will keep running to maintain the tunnel
- Keep the PowerShell window open
- Or run ngrok in a separate terminal:
  ```powershell
  ngrok http 58093
  ```
  (Replace `58093` with your Minikube port if different)

### 8. Monitor ngrok

View the ngrok dashboard at: http://localhost:4040

This shows:
- Active tunnels
- Request logs
- Public URL

## Usage Workflow

1. **Before running GitHub Actions:**
   ```powershell
   # Start Minikube
   minikube start
   
   # Start tunnel
   .\setup-minikube-tunnel.ps1
   ```

2. **Trigger GitHub Actions workflow** (push to main branch)

3. **After deployment completes:**
   - You can stop ngrok (Ctrl+C in the script window)
   - Or keep it running for more deployments

## Troubleshooting

### ngrok URL Changes

If ngrok restarts, the public URL changes. You'll need to:
1. Get the new URL from http://localhost:4040
2. Update your kubeconfig
3. Regenerate base64 and update GitHub Secrets

### Connection Timeouts

- Ensure Minikube is running: `minikube status`
- Check ngrok is active: http://localhost:4040
- Verify the tunnel is pointing to the correct port

### Certificate Errors

ngrok uses self-signed certificates. The kubeconfig update should handle this, but if you see certificate errors:
- Check that the ngrok URL in kubeconfig matches the current ngrok URL
- Try regenerating the kubeconfig

### Restore Original Kubeconfig

If you need to restore your original kubeconfig:
```powershell
# The script creates a backup automatically
Copy-Item "$env:USERPROFILE\.kube\config.backup.TIMESTAMP" "$env:USERPROFILE\.kube\config" -Force
```

Or manually edit `~/.kube/config` and change the server URL back to:
```yaml
server: https://127.0.0.1:58093
```

## Alternative: Manual Setup

If you prefer to set up manually:

1. **Start ngrok:**
   ```powershell
   ngrok http 58093
   ```

2. **Get the public URL** from http://localhost:4040

3. **Update kubeconfig:**
   ```powershell
   # Edit ~/.kube/config
   # Change: server: https://127.0.0.1:58093
   # To: server: https://YOUR_NGROK_URL.ngrok.io
   ```

4. **Generate base64:**
   ```powershell
   [Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$env:USERPROFILE\.kube\config"))
   ```

5. **Add to GitHub Secrets** as `KUBECONFIG`

## Production Recommendation

For production, use a cloud Kubernetes cluster:
- **Azure AKS** (Azure Kubernetes Service)
- **AWS EKS** (Elastic Kubernetes Service)
- **Google GKE** (Google Kubernetes Engine)
- **DigitalOcean Kubernetes**
- **Linode Kubernetes**

These provide:
- ✅ Stable endpoints
- ✅ Better security
- ✅ No tunnel maintenance
- ✅ Production-grade reliability

