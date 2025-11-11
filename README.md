# 🚀 Express.js Kubernetes Deployment

A production-ready Express.js application deployed to Kubernetes with Helm. **Local development setup with CI/CD pipeline configuration.**

## 📋 Features

- ✅ **Express.js** web application with health checks
- ✅ **Docker** containerization 
- ✅ **Kubernetes** deployment with 3 replicas
- ✅ **Helm** charts for configuration management
- ✅ **GitHub Actions CI/CD** pipeline configured
- ✅ **Health monitoring** with readiness/liveness probes
- ✅ **Load balancing** across multiple pods

## 🏗️ Architecture

```
[Application] → [Docker] → [Kubernetes] → [Service] → [External Access]
```

## 🛠️ Quick Start

### Local Development

```bash
npm install
npm start
# Access: http://localhost:3000
```

### Docker

```bash
docker build -t express-k8s-app .
docker run -p 3000:3000 express-k8s-app
```

### Kubernetes Deployment

```bash
# Using Helm
helm install express-app ./express-helm-chart

# Using raw manifests
kubectl apply -f k8s/
```

## 🔄 CI/CD Status

The GitHub Actions CI/CD pipeline is configured but requires a cloud Kubernetes cluster for full automation.

**Current Setup:**
- ✅ Tests run automatically on every push
- ✅ Docker image builds and pushes to Docker Hub
- ✅ Helm deployment configured
- ❌ Auto-deployment requires cloud Kubernetes cluster

**For Full CI/CD:**

To enable automatic deployments, you would need:
1. Cloud Kubernetes cluster (GKE, EKS, AKS)
2. Update `KUBECONFIG` secret with cloud cluster credentials
3. The pipeline will automatically deploy on every push

## 🌐 Access the Application

After local deployment:

```bash
kubectl port-forward service/express-app-service 8080:80
# Then open http://localhost:8080
```

**Endpoints:**
- `GET /` - Main application
- `GET /health` - Health checks
- `GET /info` - Application info

## 📁 Project Structure

```
express-k8s-app/
├── .github/workflows/     # CI/CD pipelines
├── express-helm-chart/    # Helm charts
├── k8s/                  # Kubernetes manifests
├── index.js              # Express application
├── package.json          # Dependencies
├── Dockerfile            # Container definition
└── README.md            # This file
```

## 🎯 Learning Outcomes

This project demonstrates:
- Containerization with Docker
- Kubernetes orchestration with multi-replica deployments
- Helm package management for Kubernetes
- Health checks and application monitoring
- CI/CD pipeline design with GitHub Actions
- Production deployment strategies

## 🚀 Production Readiness

For production deployment:
- Use a managed Kubernetes service (GKE, EKS, AKS)
- Configure proper ingress with SSL
- Set up monitoring (Prometheus, Grafana)
- Implement proper secrets management
- Add database persistence

## 📝 License

MIT License - feel free to use this project as a template!

