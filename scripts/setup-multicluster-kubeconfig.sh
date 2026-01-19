#!/bin/bash
# Script to configure kubectl for accessing multiple clusters
# Usage: ./setup-multicluster-kubeconfig.sh

echo "========================================="
echo "Setting up Multi-Cluster kubectl Access"
echo "========================================="
echo ""

# Create kubeconfig directory
mkdir -p ~/.kube/clusters

echo "1. Downloading kubeconfig from Cluster 1 (Primary)..."
read -p "Enter Master 1 IP address: " MASTER1_IP
scp ubuntu@$MASTER1_IP:~/.kube/config ~/.kube/clusters/config-cluster1

echo ""
echo "2. Downloading kubeconfig from Cluster 2 (Secondary)..."
read -p "Enter Master 2 IP address: " MASTER2_IP
scp ubuntu@$MASTER2_IP:~/.kube/config ~/.kube/clusters/config-cluster2

echo ""
echo "3. Merging kubeconfigs..."

# Set KUBECONFIG to all files
export KUBECONFIG="~/.kube/clusters/config-cluster1:~/.kube/clusters/config-cluster2"

# Merge contexts
kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config

echo ""
echo "4. Renaming contexts for clarity..."

# Get current context names
CLUSTER1_CTX=$(kubectl config get-contexts | grep cluster1 | awk '{print $1}')
CLUSTER2_CTX=$(kubectl config get-contexts | grep cluster2 | awk '{print $1}')

# Rename contexts
kubectl config rename-context $CLUSTER1_CTX cluster-1
kubectl config rename-context $CLUSTER2_CTX cluster-2

echo ""
echo "5. Available contexts:"
kubectl config get-contexts

echo ""
echo "========================================="
echo "Setup complete!"
echo ""
echo "Switch between clusters:"
echo "  kubectl config use-context cluster-1"
echo "  kubectl config use-context cluster-2"
echo ""
echo "Set KUBECONFIG environment variable:"
echo "  Linux/Mac: export KUBECONFIG=~/.kube/config"
echo "  Windows:   \$env:KUBECONFIG = \"$env:HOMEPATH\.kube\config\""
echo "========================================="
