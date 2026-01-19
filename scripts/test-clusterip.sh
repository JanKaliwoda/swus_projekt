#!/bin/bash
# Script to test Phase II - Scenario 2B (ClusterIP) from inside cluster
# Usage: kubectl exec -it <pod-name> -n swus-app -- sh, then run this script

echo "========================================="
echo "Testing Phase II - Scenario 2B (ClusterIP)"
echo "========================================="
echo ""

SERVICE_NAME="swus-server-clusterip"
NAMESPACE="swus-app"
FQDN="${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local"

echo "1. Testing with short name:"
echo "  Service: $SERVICE_NAME"
curl -s -w "HTTP Status: %{http_code}\n" http://$SERVICE_NAME || echo "FAILED"
echo ""

echo "2. Testing with full FQDN:"
echo "  FQDN: $FQDN"
curl -s -w "HTTP Status: %{http_code}\n" http://$FQDN || echo "FAILED"
echo ""

echo "3. Testing DNS resolution:"
nslookup $FQDN || echo "DNS resolution failed"
echo ""

echo "4. Load test (20 requests) - observe which Pod responds:"
echo "  (Keep eye on logs: kubectl logs -n swus-app -l app=swus-server -f)"
echo ""
for i in {1..20}; do
  echo -n "  Request $i: "
  RESPONSE=$(curl -s http://$SERVICE_NAME 2>&1)
  echo "$RESPONSE" | head -1
done
echo ""

echo "========================================="
echo "Test completed!"
echo "Note: Check Pod logs for server responses"
echo "========================================="
