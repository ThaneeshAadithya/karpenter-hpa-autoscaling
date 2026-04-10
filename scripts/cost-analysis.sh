#!/usr/bin/env bash
# cost-analysis.sh — Show spot vs on-demand cost breakdown by NodePool
set -euo pipefail

echo "==> Karpenter Node Cost Analysis"
echo ""

echo "── Nodes by capacity type ──────────────────────────────────────────"
kubectl get nodes \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.karpenter\.sh/capacity-type}{"\t"}{.metadata.labels.beta\.kubernetes\.io/instance-type}{"\n"}{end}' \
  2>/dev/null | sort | column -t

echo ""
echo "── Node utilisation ────────────────────────────────────────────────"
kubectl top nodes 2>/dev/null | sort -k3 -h || echo "(metrics-server not available)"

echo ""
echo "── Spot savings estimate ────────────────────────────────────────────"
SPOT_NODES=$(kubectl get nodes -l karpenter.sh/capacity-type=spot --no-headers 2>/dev/null | wc -l)
OD_NODES=$(kubectl get nodes -l karpenter.sh/capacity-type=on-demand --no-headers 2>/dev/null | wc -l)
TOTAL=$((SPOT_NODES + OD_NODES))

if [[ "${TOTAL}" -gt 0 ]]; then
  SPOT_PCT=$((SPOT_NODES * 100 / TOTAL))
  echo "  Spot nodes    : ${SPOT_NODES} (${SPOT_PCT}%)"
  echo "  On-Demand     : ${OD_NODES}"
  echo "  Est. savings  : ~$((SPOT_PCT * 70 / 100))% vs all On-Demand (at ~70% spot discount)"
fi
