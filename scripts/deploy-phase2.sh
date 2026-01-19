#!/bin/bash
# Quick deployment script for Phase II
# Usage: ./deploy-phase2.sh

echo "========================================="
echo "Phase II - Quick Deployment"
echo "========================================="
echo ""

# Check kubectl
if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl not found"
  exit 1
fi

echo "1. Creating namespace and Deployment..."
kubectl apply -f fase_II/01-server-deployment.yaml

echo ""
echo "2. Creating Services (NodePort + ClusterIP)..."
kubectl apply -f fase_II/02-server-services.yaml

echo ""
echo "3. Creating Client Pods..."
kubectl apply -f fase_II/03-client-pods.yaml

echo ""
echo "4. Waiting for Pods to be ready..."
sleep 5

echo ""
echo "========================================="
echo "Deployment Status:"
echo "========================================="
kubectl get all -n swus-app

echo ""
echo "========================================="
echo "Service Details:"
echo "========================================="
kubectl get svc -n swus-app

echo ""
echo "========================================="
echo "Next steps:"
echo ""
echo "Test NodePort (Scenario 2A):"
echo "  1. Get worker node IP: kubectl get nodes -o wide"
echo "  2. Or use Terraform output: terraform output worker_ip"
echo "  3. Test: curl http://<WORKER_IP>:30080"
echo ""
echo "Test ClusterIP (Scenario 2B):"
echo "  1. Enter client pod: kubectl exec -it -n swus-app swus-client-curl -- sh"
echo "  2. Inside pod, test: curl http://swus-server-clusterip.swus-app.svc.cluster.local"
echo "========================================="
