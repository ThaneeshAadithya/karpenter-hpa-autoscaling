#!/usr/bin/env bash
# watch-scaling.sh — Real-time autoscaling monitor during load tests
# Shows HPA decisions, node provisioning, and pod counts side by side
set -euo pipefail

NS="${1:-backend}"
INTERVAL="${2:-5}"

echo "==> Watching autoscaling in namespace: ${NS}"
echo "    Press Ctrl+C to stop"
echo ""

while true; do
  clear
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║  AUTOSCALING MONITOR — $(date -u '+%H:%M:%S UTC')                    ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""

  # ── HPA Status ────────────────────────────────────────────────────────────
  echo "── HPA Status ──────────────────────────────────────────────────────"
  kubectl get hpa -n "${NS}" --no-headers 2>/dev/null \
    | awk '{printf "  %-30s CURRENT=%-4s TARGET=%-4s MIN=%-4s MAX=%-4s\n", $1, $4, $5, $6, $7}' \
    || echo "  (no HPAs found)"
  echo ""

  # ── Node Pool Status ──────────────────────────────────────────────────────
  echo "── Nodes by NodePool ────────────────────────────────────────────────"
  kubectl get nodes --show-labels --no-headers 2>/dev/null \
    | awk '{
        split($0, a, " ");
        for(i=1; i<=NF; i++) {
          if ($i ~ /nodepool=/) {
            split($i, b, "=");
            pools[b[2]]++;
          }
        }
      }
      END {
        for (pool in pools)
          printf "  %-30s %d nodes\n", pool, pools[pool];
      }' \
    || echo "  (no labeled nodes found)"
  echo ""

  # ── Pending Pods ──────────────────────────────────────────────────────────
  PENDING=$(kubectl get pods -A --no-headers 2>/dev/null | grep Pending | wc -l)
  if [[ "${PENDING}" -gt 0 ]]; then
    echo "── ⚠️  Pending Pods: ${PENDING} ──────────────────────────────────────"
    kubectl get pods -A --no-headers | grep Pending | head -10
    echo ""
  fi

  # ── Pod Count ─────────────────────────────────────────────────────────────
  echo "── Pod Status (${NS}) ────────────────────────────────────────────────"
  kubectl get pods -n "${NS}" --no-headers 2>/dev/null \
    | awk '{ counts[$3]++ } END { for (s in counts) printf "  %-15s %d\n", s, counts[s] }' \
    || echo "  (no pods found)"
  echo ""

  # ── Karpenter NodeClaims ──────────────────────────────────────────────────
  echo "── NodeClaims (Karpenter) ───────────────────────────────────────────"
  kubectl get nodeclaim --no-headers 2>/dev/null | head -10 \
    || echo "  (no nodeclaims — Karpenter may not be installed)"

  echo ""
  echo "Refreshing in ${INTERVAL}s..."
  sleep "${INTERVAL}"
done
