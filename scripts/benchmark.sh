#!/usr/bin/env bash
# benchmark.sh — Measure HPA + Karpenter scale time end-to-end
# Runs a surge, records timestamps, calculates scale-out duration
set -euo pipefail

NS="${1:-backend}"
DEPLOY="${2:-backend-api}"
TARGET_REPLICAS="${3:-10}"
BASE_URL="${4:-http://backend-api.backend.svc.cluster.local}"

echo "==> Autoscaling Benchmark"
echo "    Namespace  : ${NS}"
echo "    Deployment : ${DEPLOY}"
echo "    Target pods: ${TARGET_REPLICAS}"
echo ""

# Record baseline
BASELINE_PODS=$(kubectl get deployment "${DEPLOY}" -n "${NS}" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
BASELINE_NODES=$(kubectl get nodes --no-headers | grep -c Ready || echo "0")

echo "Baseline: ${BASELINE_PODS} pods, ${BASELINE_NODES} nodes"
echo ""

# Start load test in background
echo "--> Starting k6 surge test..."
k6 run load-tests/k6/surge-test.js \
  --env BASE_URL="${BASE_URL}" \
  --no-summary \
  --quiet &
K6_PID=$!

SURGE_START=$(date +%s)
echo "--> Surge started at $(date -u '+%H:%M:%S UTC')"

# Wait for pods to scale
echo "--> Waiting for pods to reach ${TARGET_REPLICAS}..."
while true; do
  CURRENT=$(kubectl get deployment "${DEPLOY}" -n "${NS}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  CURRENT_NODES=$(kubectl get nodes --no-headers | grep -c Ready || echo "0")

  echo "  $(date -u '+%H:%M:%S') — Pods: ${CURRENT}/${TARGET_REPLICAS} | Nodes: ${CURRENT_NODES}"

  if [[ "${CURRENT}" -ge "${TARGET_REPLICAS}" ]]; then
    SCALE_END=$(date +%s)
    SCALE_TIME=$((SCALE_END - SURGE_START))
    echo ""
    echo "✅ Scale-out complete!"
    echo "   Pods ready     : ${CURRENT}"
    echo "   Nodes ready    : ${CURRENT_NODES}"
    echo "   Scale time     : ${SCALE_TIME}s"
    echo "   Node delta     : +$((CURRENT_NODES - BASELINE_NODES)) nodes"
    echo "   Pod delta      : +$((CURRENT - BASELINE_PODS)) pods"
    [[ "${SCALE_TIME}" -le 90 ]] && \
      echo "   🎯 SLO MET: scale within 90s" || \
      echo "   ⚠️  SLO MISSED: scale took > 90s"
    break
  fi

  sleep 5
done

# Stop k6
kill "${K6_PID}" 2>/dev/null || true
echo ""
echo "Benchmark complete."
