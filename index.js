const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;
const HOST = '0.0.0.0';  // Explicitly bind to all interfaces

// Middleware
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    message: 'Health check passed'
  });
});

// Main endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Kubernetes! 🚀',
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development',
    host: req.headers.host,
    server: 'Express.js on Node ' + process.version
  });
});

// Info endpoint
app.get('/info', (req, res) => {
  res.json({
    app: 'Express Kubernetes Demo',
    nodeVersion: process.version,
    platform: process.platform,
    memory: process.memoryUsage(),
    env: process.env.NODE_ENV || 'development'
  });
});

// Start server with explicit host binding
app.listen(PORT, HOST, () => {
  console.log(`✅ Server running on http://${HOST}:${PORT}`);
  console.log(`✅ Health check: http://${HOST}:${PORT}/health`);
  console.log(`✅ Main endpoint: http://${HOST}:${PORT}/`);
  console.log(`✅ Info endpoint: http://${HOST}:${PORT}/info`);
});

// Handle graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  process.exit(0);
});