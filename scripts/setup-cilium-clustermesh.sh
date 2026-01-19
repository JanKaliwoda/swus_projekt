#!/bin/bash
# Cilium Cluster Mesh Setup Script
# This script automates the setup of Cluster Mesh between two clusters

CLUSTER1_CONTEXT="cluster-1"
CLUSTER2_CONTEXT="cluster-2"

echo "========================================="
echo "Cilium Cluster Mesh Setup"
echo "========================================="
echo ""

# Function to check if context exists
check_context() {
  if ! kubectl config get-contexts | grep -q "^[[:space:]]*$1[[:space:]]"; then
    echo "ERROR: Context $1 not found"
    echo "Available contexts:"
    kubectl config get-contexts
    exit 1
  fi
}

# Function to check if Helm is installed
check_helm() {
  if ! command -v helm &> /dev/null; then
    echo "ERROR: Helm is not installed"
    echo "Please install Helm from https://helm.sh"
    exit 1
  fi
}

# Validate setup
echo "1. Validating environments..."
check_context $CLUSTER1_CONTEXT
check_context $CLUSTER2_CONTEXT
check_helm

# Add Cilium Helm repo
echo ""
echo "2. Adding Cilium Helm repository..."
helm repo add cilium https://helm.cilium.io
helm repo update

# Install Cilium on Cluster 1
echo ""
echo "3. Installing Cilium on Cluster 1..."
kubectl config use-context $CLUSTER1_CONTEXT

helm install cilium cilium/cilium \
  --namespace cilium \
  --create-namespace \
  --set cluster.id=1 \
  --set cluster.name=cluster-1 \
  --set clustermesh.apiserver.enabled=true \
  --set clustermesh.apiserver.service.type=NodePort \
  --set clustermesh.apiserver.service.nodePort=32379 \
  --wait

echo "Waiting for Cilium on Cluster 1..."
sleep 10

# Install Cilium on Cluster 2
echo ""
echo "4. Installing Cilium on Cluster 2..."
kubectl config use-context $CLUSTER2_CONTEXT

helm install cilium cilium/cilium \
  --namespace cilium \
  --create-namespace \
  --set cluster.id=2 \
  --set cluster.name=cluster-2 \
  --set clustermesh.apiserver.enabled=true \
  --set clustermesh.apiserver.service.type=NodePort \
  --set clustermesh.apiserver.service.nodePort=32379 \
  --wait

echo "Waiting for Cilium on Cluster 2..."
sleep 10

# Get cluster mesh config from Cluster 2
echo ""
echo "5. Extracting Cluster 2 configuration..."

kubectl config use-context $CLUSTER2_CONTEXT

# Get CA certificate
kubectl get secret -n cilium cilium-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/ca-cluster2.crt

# Get APIServer service details
echo ""
echo "Getting Cluster 2 APIServer IP..."
CLUSTER2_APISERVER_IP=$(kubectl get svc -n cilium clustermesh-apiserver -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$CLUSTER2_APISERVER_IP" ]; then
  echo "Note: LoadBalancer IP not yet assigned. Getting ClusterIP instead..."
  CLUSTER2_APISERVER_IP=$(kubectl get svc -n cilium clustermesh-apiserver -o jsonpath='{.spec.clusterIP}')
fi

echo "Cluster 2 APIServer IP: $CLUSTER2_APISERVER_IP"

# Configure Cluster 1 for Mesh with Cluster 2
echo ""
echo "6. Configuring Cluster 1 for Cluster Mesh..."

kubectl config use-context $CLUSTER1_CONTEXT

# Create secret with Cluster 2 CA
kubectl create secret generic -n cilium clustermesh-secrets-cluster-2 \
  --from-file=ca.crt=/tmp/ca-cluster2.crt \
  --from-literal=api-server-ip=$CLUSTER2_APISERVER_IP \
  --from-literal=api-server-port=32379 \
  2>/dev/null || echo "Secret may already exist"

# Wait for mesh to establish
echo ""
echo "7. Waiting for Cluster Mesh to establish connection..."
sleep 15

# Verify mesh status
echo ""
echo "8. Verifying Cluster Mesh status..."

echo ""
echo "=== Cluster 1 Status ==="
kubectl config use-context $CLUSTER1_CONTEXT
kubectl get pods -n cilium | grep -i mesh

echo ""
echo "=== Cluster 2 Status ==="
kubectl config use-context $CLUSTER2_CONTEXT
kubectl get pods -n cilium | grep -i mesh

echo ""
echo "========================================="
echo "Cluster Mesh setup complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Deploy server on Cluster 2:"
echo "   kubectl apply -f fase_III/02-server-deployment-secondary.yaml"
echo ""
echo "2. Mark service as global:"
echo "   kubectl annotate service swus-server-secondary-clusterip -n swus-app-secondary io.cilium/global-service=true"
echo ""
echo "3. Test communication from Cluster 1 client Pod"
echo ""
echo "Cleanup:"
echo "rm /tmp/ca-cluster2.crt"
