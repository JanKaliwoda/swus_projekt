#!/bin/bash
# Script to test Phase II - Scenario 2A (NodePort)
# Usage: ./test-nodeport.sh <WORKER_NODE_IP>

if [ -z "$1" ]; then
  echo "Usage: $0 <WORKER_NODE_IP>"
  echo "Example: $0 34.89.12.45"
  exit 1
fi

WORKER_IP=$1
NODE_PORT=30080

echo "========================================="
echo "Testing Phase II - Scenario 2A (NodePort)"
echo "========================================="
echo "Target: http://$WORKER_IP:$NODE_PORT"
echo ""

# Test basic connectivity
echo "1. Basic connectivity test:"
curl -s -w "HTTP Status: %{http_code}\n" http://$WORKER_IP:$NODE_PORT || echo "FAILED"
echo ""

# Test with verbose output
echo "2. Verbose test (headers):"
curl -v http://$WORKER_IP:$NODE_PORT 2>&1 | grep -E "Connected|HTTP|"
echo ""

# Test multiple endpoints (if available)
echo "3. Testing endpoints:"
for endpoint in "" "/health" "/api/status" "/metrics"; do
  echo -n "  $endpoint: "
  curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$WORKER_IP:$NODE_PORT$endpoint
done
echo ""

# Stress test with multiple requests
echo "4. Load test (10 requests):"
for i in {1..10}; do
  echo -n "  Request $i: "
  curl -s -w "HTTP %{http_code}\n" http://$WORKER_IP:$NODE_PORT > /dev/null
done
echo ""

echo "========================================="
echo "Test completed!"
echo "========================================="
