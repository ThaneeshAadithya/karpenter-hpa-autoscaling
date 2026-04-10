
.PHONY: help deploy-karpenter apply-pools apply-hpa surge-test watch benchmark

NS       ?= backend
DEPLOY   ?= backend-api
BASE_URL ?= http://backend-api.backend.svc.cluster.local

help:
	@echo "Targets:"
	@echo "  deploy-karpenter  Deploy Karpenter via Terraform"
	@echo "  apply-pools       Apply NodePools and EC2NodeClass"
	@echo "  apply-hpa         Apply HPA configs"
	@echo "  surge-test        Run k6 2-3x surge test"
	@echo "  soak-test         Run k6 30-min soak test"
	@echo "  spike-test        Run k6 instantaneous spike test"
	@echo "  watch             Watch scaling events in real time"
	@echo "  benchmark         Measure end-to-end scale time"
	@echo "  cost              Show spot vs on-demand cost breakdown"

deploy-karpenter:
	cd terraform/irsa && terraform init && terraform apply
	cd terraform/karpenter && terraform init && terraform apply

apply-pools:
	kubectl apply -f karpenter/node-classes/
	kubectl apply -f karpenter/node-pools/
	kubectl apply -f karpenter/disruption/pod-disruption-budgets.yaml

apply-hpa:
	kubectl apply -f apps/sample-app/
	kubectl apply -f hpa/configs/

surge-test:
	k6 run load-tests/k6/surge-test.js --env BASE_URL=$(BASE_URL)

soak-test:
	k6 run load-tests/k6/soak-test.js --env BASE_URL=$(BASE_URL)

spike-test:
	k6 run load-tests/k6/spike-test.js --env BASE_URL=$(BASE_URL)

watch:
	./scripts/watch-scaling.sh $(NS)

benchmark:
	./scripts/benchmark.sh $(NS) $(DEPLOY) 10 $(BASE_URL)

cost:
	./scripts/cost-analysis.sh
