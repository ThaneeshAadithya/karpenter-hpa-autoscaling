# Autoscaling Tuning Guide

## HPA Tuning

### Resource Request Sizing — The Foundation

HPA accuracy depends entirely on correct resource requests.
The formula: `current_utilization = actual_usage / request`

If `request` is wrong, HPA fires at the wrong time:
- Too low → HPA thinks pods are overloaded, scales too aggressively
- Too high → HPA thinks pods have headroom, scales too late

**How to measure correct requests:**
Run `kubectl top pods` over several days, use P90 CPU as your request value.
Use VPA in Off mode to get recommendations without auto-applying them.

### Scale-Up Threshold Selection

| Threshold | Behaviour | Risk |
|-----------|-----------|------|
| 50% CPU | Scales early, lots of headroom | Over-provisioned, expensive |
| 60-70% CPU | Balanced — recommended | Good default |
| 80%+ CPU | Scales late | Latency spikes during surge |

For surge handling, **60% is the sweet spot** — gives HPA time to scale before pods saturate.

### Stabilisation Windows

Never add a stabilisation window to scale-up — it delays response to surges.
Always add 5–10 min to scale-down — prevents flapping.

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0      # Scale up IMMEDIATELY
  scaleDown:
    stabilizationWindowSeconds: 300    # Wait 5 min before scaling down
```

---

## Karpenter Tuning

### NodePool Instance Selection

Wide instance selection = faster provisioning (more AZ/type options).
Use instance-category + instance-generation rather than specific types.

### Spot Mix Strategy

For maximum spot availability, use 5+ instance families:
m5, m5a, m5n, m6i, m6a, m6in — all similar specs, different hardware.
Karpenter picks cheapest available option across all AZs automatically.

### Consolidation Settings

| Environment | Policy | Delay | Why |
|-------------|--------|-------|-----|
| Dev | WhenEmptyOrUnderutilized | 30s | Reduce cost aggressively |
| Staging | WhenEmptyOrUnderutilized | 1m | Moderate |
| Prod | WhenEmpty | 5m | Conservative — avoid disruption |

### Disruption Budget (Business Hours Protection)

```yaml
disruption:
  budgets:
    - nodes: "10%"              # Max 10% nodes disrupted at any time
    - schedule: "30 3 * * 1-5" # Mon-Fri 9am IST = 3:30am UTC
      duration: 9h
      nodes: "0"               # Zero disruptions during business hours
```

---

## The 90-Second Rule

To consistently achieve surge handling in < 90 seconds:

1. **HPA fires in < 30s** — requires Prometheus scrape interval ≤ 15s
2. **Pods start in < 15s** — requires fast startup probe and pre-pulled images
3. **Karpenter provisions in < 60s** — requires Nitro instances, wide type selection

### Pre-warming Strategy

Keep 1 warm node in the burst pool by deploying a lightweight placeholder pod
that tolerates the spot-burst taint. This keeps one spot node alive so the
first surge pods schedule immediately without waiting for node provisioning.
