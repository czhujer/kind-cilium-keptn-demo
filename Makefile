# Set environment variables
export CLUSTER_NAME?=keptn
export CILIUM_VERSION?=1.11.3
export CERT_MANAGER_CHART_VERSION=1.8.0
export ARGOCD_CHART_VERSION=4.5.7
export KEPTN_VERSION?=0.13.2
export TRIVY_IMAGE_CHECK=1

export ARGOCD_OPTS="--grpc-web --insecure --server argocd.127.0.0.1.nip.io"

# kind image list
#for kind v0.11.x
# image: kindest/node:v1.21.2@sha256:9d07ff05e4afefbba983fac311807b3c17a5f36e7061f6cb7e2ba756255b2be4
# image: kindest/node:v1.22.5@sha256:d409e1b1b04d3290195e0263e12606e1b83d5289e1f80e54914f60cd1237499d
# image: kindest/node:v1.23.3@sha256:0df8215895129c0d3221cda19847d1296c4f29ec93487339149333bd9d899e5a
#for kind v0.11.x
# export KIND_NODE_IMAGE="kindest/node:v1.23.4@sha256:1742ff7f0b79a8aaae347b9c2ffaf9738910e721d649301791c812c162092753"
#for kind v0.12.x
# kindest/node:v1.21.10@sha256:84709f09756ba4f863769bdcabe5edafc2ada72d3c8c44d6515fc581b66b029c
# kindest/node:v1.22.7@sha256:1dfd72d193bf7da64765fd2f2898f78663b9ba366c2aa74be1fd7498a1873166
# kindest/node:v1.23.4@sha256:0e34f0d0fd448aa2f2819cfd74e99fe5793a6e4938b328f657c8e3f81ee0dfb9
export KIND_NODE_IMAGE="kindest/node:v1.23.5@sha256:a69c29d3d502635369a5fe92d8e503c09581fcd406ba6598acc5d80ff5ba81b1"

.PHONY: kind-basic
kind-basic: kind-create kx-kind kind-install-crds cilium-prepare-images cilium-install argocd-deploy nginx-ingress-deploy

.PHONY: kind-keptn
kind-keptn: kind-basic prometheus-stack-deploy keptn-prepare-images keptn-deploy

.PHONY: kind-spo
kind-spo: kind-basic cert-manager-deploy spo-deploy

.PHONY: kind-create
kind-create:
ifeq ($(TRIVY_IMAGE_CHECK), 1)
	trivy image --severity=HIGH --exit-code=0 "$(KIND_NODE_IMAGE)"
endif
	kind --version
	kind create cluster --name "$(CLUSTER_NAME)" \
 		--config="kind/kind-config.yaml" \
 		--image="$(KIND_NODE_IMAGE)"
# for testing PSP
#	kubectl apply -f https://github.com/appscodelabs/tasty-kube/raw/master/psp/privileged-psp.yaml
#	kubectl apply -f https://github.com/appscodelabs/tasty-kube/raw/master/psp/baseline-psp.yaml
#	kubectl apply -f https://github.com/appscodelabs/tasty-kube/raw/master/psp/restricted-psp.yaml
#	kubectl apply -f https://github.com/appscodelabs/tasty-kube/raw/master/kind/psp/cluster-roles.yaml
#	kubectl apply -f https://github.com/appscodelabs/tasty-kube/raw/master/kind/psp/role-bindings.yaml
# for more control planes, but no workers
# kubectl taint nodes --all node-role.kubernetes.io/master- || true

.PHONY: kind-delete
kind-delete:
	kind delete cluster --name $(CLUSTER_NAME)

.PHONY: kx-kind
kx-kind:
	kind export kubeconfig --name $(CLUSTER_NAME)

.PHONY: kind-install-crds
kind-install-crds:
	# fix prometheus-operator's CRDs
	kubectl apply -f https://raw.githubusercontent.com/prometheus-community/helm-charts/main/charts/kube-prometheus-stack/crds/crd-servicemonitors.yaml
	# for keptn
	kubectl apply -f keptn/crd-istio-destinationrules.yaml \
				  -f keptn/crd-istio-virtualservices.yaml
	# https://raw.githubusercontent.com/keptn-sandbox/keptn-in-a-box/master/resources/istio/public-gateway.yaml

.PHONY: cilium-prepare-images
cilium-prepare-images:
	# pull image locally
	docker pull quay.io/cilium/cilium:v$(CILIUM_VERSION)
	docker pull quay.io/cilium/hubble-ui:v0.8.5
	docker pull quay.io/cilium/hubble-ui-backend:v0.8.5
	docker pull quay.io/cilium/hubble-relay:v$(CILIUM_VERSION)
	docker pull docker.io/envoyproxy/envoy:v1.18.4@sha256:e5c2bb2870d0e59ce917a5100311813b4ede96ce4eb0c6bfa879e3fbe3e83935
ifeq ($(TRIVY_IMAGE_CHECK), 1)
	trivy image --severity=HIGH --exit-code=0 quay.io/cilium/cilium:v$(CILIUM_VERSION)
	trivy image --severity=HIGH --exit-code=0 quay.io/cilium/hubble-ui:v0.8.5
	trivy image --severity=HIGH --exit-code=0 quay.io/cilium/hubble-ui-backend:v0.8.5
	trivy image --severity=HIGH --exit-code=0 quay.io/cilium/hubble-relay:v$(CILIUM_VERSION)
	trivy image --severity=HIGH --exit-code=0 docker.io/envoyproxy/envoy:v1.18.4@sha256:e5c2bb2870d0e59ce917a5100311813b4ede96ce4eb0c6bfa879e3fbe3e83935
endif
	# Load the image onto the cluster
	kind load docker-image --name $(CLUSTER_NAME) quay.io/cilium/cilium:v$(CILIUM_VERSION)
	kind load docker-image --name $(CLUSTER_NAME) quay.io/cilium/hubble-ui:v0.8.5
	kind load docker-image --name $(CLUSTER_NAME) quay.io/cilium/hubble-ui-backend:v0.8.5
	kind load docker-image --name $(CLUSTER_NAME) quay.io/cilium/hubble-relay:v$(CILIUM_VERSION)
	kind load docker-image --name $(CLUSTER_NAME) docker.io/envoyproxy/envoy:v1.18.4@sha256:e5c2bb2870d0e59ce917a5100311813b4ede96ce4eb0c6bfa879e3fbe3e83935

.PHONY: cilium-install
cilium-install:
	# Add the Cilium repo
	helm repo add cilium https://helm.cilium.io/
	# install/upgrade the chart
	helm upgrade --install cilium cilium/cilium --version $(CILIUM_VERSION) \
	   -f kind/kind-values-cilium.yaml \
	   -f kind/kind-values-cilium-hubble.yaml \
	   -f kind/kind-values-cilium-service-monitors.yaml \
	   --namespace kube-system \
	   --wait

.PHONY: cert-manager-deploy
cert-manager-deploy:
	# prepare image(s)
	docker pull quay.io/jetstack/cert-manager-controller:v1.7.1
	docker pull quay.io/jetstack/cert-manager-webhook:v1.7.1
	docker pull quay.io/jetstack/cert-manager-cainjector:v1.7.1
	docker pull quay.io/jetstack/cert-manager-ctl:v1.7.1
	kind load docker-image --name $(CLUSTER_NAME) quay.io/jetstack/cert-manager-controller:v1.7.1
	kind load docker-image --name $(CLUSTER_NAME) quay.io/jetstack/cert-manager-webhook:v1.7.1
	kind load docker-image --name $(CLUSTER_NAME) quay.io/jetstack/cert-manager-cainjector:v1.7.1
	kind load docker-image --name $(CLUSTER_NAME) quay.io/jetstack/cert-manager-ctl:v1.7.1
	#
	helm repo add cert-manager https://charts.jetstack.io
	helm upgrade --install \
		cert-manager cert-manager/cert-manager \
		--version "${CERT_MANAGER_CHART_VERSION}" \
	   --namespace cert-manager \
	   --create-namespace \
	   --values kind/cert-manager.yaml \
	   --wait

.PHONY: argocd-deploy
argocd-deploy:
	# prepare image(s)
	docker pull quay.io/argoproj/argocd:v2.3.3
	docker pull quay.io/argoproj/argocd-applicationset:v0.4.1
	docker pull redis:6.2.6-alpine
	docker pull bitnami/redis-exporter:1.26.0-debian-10-r2
	kind load docker-image --name $(CLUSTER_NAME) quay.io/argoproj/argocd:v2.3.3
	kind load docker-image --name $(CLUSTER_NAME) quay.io/argoproj/argocd-applicationset:v0.4.1
	kind load docker-image --name $(CLUSTER_NAME) redis:6.2.6-alpine
	kind load docker-image --name $(CLUSTER_NAME) bitnami/redis-exporter:1.26.0-debian-10-r2
	# install
	helm repo add argo https://argoproj.github.io/argo-helm
	helm upgrade --install \
		argocd-single \
		argo/argo-cd \
		--namespace argocd \
		--create-namespace \
		--version "${ARGOCD_CHART_VERSION}" \
		-f kind/kind-values-argocd.yaml \
		-f kind/kind-values-argocd-service-monitors.yaml \
		--wait
	# update CRDs
	kubectl -n argocd apply -f argocd/argo-cd-crds.yaml
	# kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""

.PHONY: spo-deploy
spo-deploy:
	# wait to cert-manager up and running
	kubectl wait -n cert-manager --timeout=2m --for=condition=available deployment cert-manager
	kubectl wait -n cert-manager --timeout=2m --for=condition=available deployment cert-manager-webhook
	kubectl wait -n cert-manager --timeout=2m --for=condition=available deployment cert-manager-cainjector
	# install over argo-cd
#	kubectl -n argocd apply -f argocd/projects/security-profiles-operator.yaml
#	kubectl -n argocd apply -f argocd/security-profiles-operator.yaml
	# install over kubectl
	kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/security-profiles-operator/v0.4.1/deploy/operator.yaml
	# wait to spo up and running
	sleep 2
	kubectl -n security-profiles-operator wait --for condition=ready ds/spod
	kubectl -n security-profiles-operator patch deployments.apps security-profiles-operator --type=merge -p '{"spec":{"replicas":1}}'
	kubectl -n security-profiles-operator patch deployments.apps security-profiles-operator-webhook --type=merge -p '{"spec":{"replicas":1}}'
	kubectl -n security-profiles-operator patch spod spod --type=merge -p '{"spec":{"hostProcVolumePath":"/hostproc"}}'
	kubectl -n security-profiles-operator patch spod spod --type=merge -p '{"spec":{"enableLogEnricher":true}}' # DOCKER DESKTOP ONLY

.PHONY: nginx-ingress-deploy
nginx-ingress-deploy:
	docker pull k8s.gcr.io/ingress-nginx/controller:v1.2.0
	kind load docker-image --name $(CLUSTER_NAME) k8s.gcr.io/ingress-nginx/controller:v1.2.0
	# ingress
	kubectl -n argocd apply -f argocd/nginx-ingress.yaml
	kubectl -n argocd apply -f argocd/gateway-api-crds.yaml
#	helm repo add --force-update ingress-nginx https://kubernetes.github.io/ingress-nginx
#	helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
#	  --namespace ingress-nginx \
#	  --create-namespace \
#	-f kind/kind-values-ingress-nginx.yaml
#
#	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
#	kubectl delete validatingwebhookconfigurations.admissionregistration.k8s.io ingress-nginx-admission

.PHONY: metrics-server-deploy
metrics-server-deploy:
	kubectl -n argocd apply -f argocd/projects/system-kube.yaml
	kubectl -n argocd apply -f argocd/metrics-server.yaml

.PHONY: prometheus-stack-deploy
prometheus-stack-deploy:
	# projects
	kubectl -n argocd apply -f argocd/projects/system-monitoring.yaml
	# (update) CRDs
	kubectl -n argocd apply -f argocd/prometheus-stack-crds.yaml
	sleep 10
	#monitoring
	kubectl -n argocd apply -f argocd/prometheus-stack.yaml
	kubectl -n argocd apply -f argocd/prometheus-adapter.yaml
	# old way
#	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
#	helm upgrade --install \
#	prometheus-stack \
#	prometheus-community/kube-prometheus-stack \
#	--namespace monitoring \
#    --create-namespace \
#    -f kind/kind-values-prometheus.yaml

.PHONY: starboard-deploy
starboard-deploy:
	# projects
	kubectl -n argocd apply -f argocd/projects/security-starboard.yaml
	# (update) CRDs
	kubectl -n argocd apply -f argocd/security-starboard.yaml

.PHONY: keptn-prepare-images
keptn-prepare-images:
	# pull image locally
	docker pull docker.io/bitnami/mongodb:4.4.9-debian-10-r0
	docker pull docker.io/keptn/distributor:$(KEPTN_VERSION)
	docker pull docker.io/keptn/mongodb-datastore:$(KEPTN_VERSION)
	docker pull docker.io/keptn/bridge2:$(KEPTN_VERSION)
	docker pull nats:2.1.9-alpine3.12
	docker pull synadia/prometheus-nats-exporter:0.5.0
	docker pull docker.io/keptn/shipyard-controller:$(KEPTN_VERSION)
	docker pull docker.io/keptn/jmeter-service:$(KEPTN_VERSION)
	docker pull docker.io/keptn/helm-service:$(KEPTN_VERSION)
	docker pull keptncontrib/prometheus-service:0.7.2
	docker pull keptncontrib/argo-service:0.9.1
	docker pull docker.io/keptn/distributor:0.10.0
ifeq ($(TRIVY_IMAGE_CHECK), 1)
	trivy image --severity=HIGH --exit-code=0 docker.io/bitnami/mongodb:4.4.9-debian-10-r0
	trivy image --severity=HIGH --exit-code=1 docker.io/keptn/distributor:$(KEPTN_VERSION)
	trivy image --severity=HIGH --exit-code=0 docker.io/keptn/mongodb-datastore:$(KEPTN_VERSION)
	trivy image --severity=HIGH --exit-code=0 docker.io/keptn/bridge2:$(KEPTN_VERSION)
	trivy image --severity=HIGH --exit-code=0 nats:2.1.9-alpine3.12
	trivy image --severity=HIGH --exit-code=1 synadia/prometheus-nats-exporter:0.5.0
	trivy image --severity=HIGH --exit-code=1 docker.io/keptn/shipyard-controller:$(KEPTN_VERSION)
	trivy image --severity=HIGH --exit-code=0 docker.io/keptn/jmeter-service:$(KEPTN_VERSION)
	trivy image --severity=HIGH --exit-code=0 docker.io/keptn/helm-service:$(KEPTN_VERSION)
	trivy image --severity=HIGH --exit-code=0 keptncontrib/prometheus-service:0.7.2
	trivy image --severity=HIGH --exit-code=0 keptncontrib/argo-service:0.9.1
	trivy image --severity=HIGH --exit-code=0 docker.io/keptn/distributor:0.10.0
endif
	# Load the image onto the cluster
	kind load docker-image --name $(CLUSTER_NAME) docker.io/bitnami/mongodb:4.4.9-debian-10-r0
	kind load docker-image --name $(CLUSTER_NAME) docker.io/keptn/distributor:$(KEPTN_VERSION)
	kind load docker-image --name $(CLUSTER_NAME) docker.io/keptn/mongodb-datastore:$(KEPTN_VERSION)
	kind load docker-image --name $(CLUSTER_NAME) docker.io/keptn/bridge2:$(KEPTN_VERSION)
	kind load docker-image --name $(CLUSTER_NAME) nats:2.1.9-alpine3.12
	kind load docker-image --name $(CLUSTER_NAME) synadia/prometheus-nats-exporter:0.5.0
	kind load docker-image --name $(CLUSTER_NAME) docker.io/keptn/shipyard-controller:$(KEPTN_VERSION)
	kind load docker-image --name $(CLUSTER_NAME) docker.io/keptn/jmeter-service:$(KEPTN_VERSION)
	kind load docker-image --name $(CLUSTER_NAME) docker.io/keptn/helm-service:$(KEPTN_VERSION)
	kind load docker-image --name $(CLUSTER_NAME) keptncontrib/prometheus-service:0.7.2
	kind load docker-image --name $(CLUSTER_NAME) keptncontrib/argo-service:0.9.1
	kind load docker-image --name $(CLUSTER_NAME) docker.io/keptn/distributor:0.10.0

.PHONY: keptn-deploy
keptn-deploy:
	kubectl -n argocd apply -f argocd/argo-rollouts.yaml
	kubectl -n argocd apply -f argocd/projects/system-keptn.yaml
	kubectl -n argocd apply -f argocd/keptn.yaml
#	helm repo add keptn https://charts.keptn.sh
#	helm upgrade --install \
#		keptn keptn/keptn \
#		-n keptn \
#		--create-namespace \
#		--wait \
#		-f kind/kind-values-keptn.yaml
#	helm upgrade --install \
#		helm-service \
#		https://github.com/keptn/keptn/releases/download/$(KEPTN_VERSION)/helm-service-$(KEPTN_VERSION).tgz \
#		-n keptn
#	helm upgrade --install \
#		jmeter-service https://github.com/keptn/keptn/releases/download/0.8.4/jmeter-service-0.8.4.tgz \
#		-n keptn
#	helm upgrade --install \
#			-n keptn \
#		  prometheus-service \
#		  https://github.com/keptn-contrib/prometheus-service/releases/download/0.7.2/prometheus-service-0.7.2.tgz \
#		  --set=prometheus.endpoint="http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090"
#	helm upgrade --install \
#			-n keptn \
#			argo-service \
#			https://github.com/keptn-contrib/argo-service/releases/download/0.9.1/argo-service-0.9.1.tgz
#	#
#	kubectl apply -n monitoring \
# 		-f https://raw.githubusercontent.com/keptn-contrib/prometheus-service/0.7.2/deploy/role.yaml

.PHONY: keptn-gitops-operator-deploy
keptn-gitops-operator-deploy:
	kubectl -n argocd apply -f argocd/projects/system-keptn.yaml
	kubectl -n argocd apply -f argocd/keptn-gitops-operator.yaml

.PHONY: keptn-set-login
keptn-set-login:
	kubectl create secret -n keptn generic bridge-credentials --from-literal="BASIC_AUTH_USERNAME=admin" --from-literal="BASIC_AUTH_PASSWORD=admin" -oyaml --dry-run=client | kubectl replace -f -
	kubectl -n keptn rollout restart deployment bridge
	keptn auth -n keptn --endpoint="http://bridge.127.0.0.1.nip.io"
	# keptn configure bridge –action=expose

.PHONY: keptn-create-project-podtato-head
keptn-create-project-podtato-head:
	keptn create project podtato-head --shipyard=keptn/podtato-head/shipyard.yaml
	keptn create service helloservice --project=podtato-head
	keptn add-resource --project=podtato-head --service=helloservice --all-stages --resource=./helm/helloservice.tgz
	echo "Adding keptn quality-gates to project podtato-head"
	keptn add-resource --project=podtato-head --stage=dev --service=helloservice --resource=keptn/podtato-head/prometheus/sli.yaml --resourceUri=prometheus/sli.yaml
	keptn add-resource --project=podtato-head --stage=dev --service=helloservice --resource=keptn/podtato-head/slo.yaml --resourceUri=slo.yaml
	#
	echo "Adding jmeter load tests to project podtato-head"
	keptn add-resource --project=podtato-head --stage=dev --service=helloservice --resource=keptn/podtato-head/jmeter/load.jmx --resourceUri=jmeter/load.jmx
	keptn add-resource --project=podtato-head --stage=dev --service=helloservice --resource=keptn/podtato-head/jmeter/jmeter.conf.yaml --resourceUri=jmeter/jmeter.conf.yaml
	echo "enable prometheus monitoring"
	keptn configure monitoring prometheus --project=podtato-head --service=helloservice
	echo "trigger delivery"
	keptn trigger delivery --project=podtato-head --service=helloservice \
		--image ghcr.io/podtato-head/podtatoserver:v0.1.1 \
		--values "replicaCount=2" \
		--values "serviceMonitor.enabled=true" \
		--values "serviceMonitor.interval=5s" --values "serviceMonitor.scrapeTimeout=5s"
	#
	# keptn trigger evaluation --project=podtato-head --service=helloservice --stage=dev --timeframe=5m

.PHONY: keptn-deploy-correct-version-podtato-head
keptn-deploy-correct-version-podtato-head:
	keptn trigger delivery --project=podtato-head --service=helloservice \
			--image ghcr.io/podtato-head/podtatoserver:v0.1.1 \
			--values "replicaCount=2" \
			--values "serviceMonitor.enabled=true" \
			--values "serviceMonitor.interval=5s" --values "serviceMonitor.scrapeTimeout=5s"

.PHONY: keptn-deploy-slow-version-podtato-head
keptn-deploy-slow-version-podtato-head:
	keptn trigger delivery --project=podtato-head --service=helloservice \
			--image="ghcr.io/podtato-head/podtatoserver" --tag=v0.1.2

.PHONY: prepare-helm-charts
prepare-helm-charts:
	helm package ./helm/helloserver/ -d helm && mv helm/helloserver-`cat helm/helloserver/Chart.yaml |yq eval '.version' - |tr -d '\n'`.tgz helm/helloservice.tgz

.PHONY: keptn-redeploy-chart-podtato-head
keptn-redeploy-chart-podtato-head:
	make prepare-helm-charts && \
	keptn add-resource --project=podtato-head --service=helloservice --all-stages --resource=./helm/helloservice.tgz && \
	make keptn-deploy-correct-version-podtato-head

.PHONY: keptn-delete-project-podtato-head
keptn-delete-project-podtato-head:
	keptn delete project podtato-head
	kubectl delete ns podtato-head-dev || true
	kubectl delete ns podtato-head-prod || true
	# keptn delete service helloservice -p podtato-head

.PHONY: keptn-create-project-sockshop
keptn-create-project-sockshop:
	keptn create project sockshop --shipyard=keptn/sockshop/shipyard.yaml
	keptn create service carts --project=sockshop
	keptn add-resource --project=sockshop --stage=prod --service=carts --resource=keptn/sockshop/jmeter/load.jmx --resourceUri=jmeter/load.jmx
	keptn add-resource --project=sockshop --stage=prod --service=carts --resource=keptn/sockshop/slo-quality-gates.yaml --resourceUri=slo.yaml
	keptn configure monitoring prometheus --project=sockshop --service=carts
	keptn add-resource --project=sockshop --stage=prod --service=carts --resource=keptn/sockshop/sli-config-argo-prometheus.yaml --resourceUri=prometheus/sli.yaml
	#
	argocd app create --name carts-prod \
		--repo https://github.com/keptn/examples.git --dest-server https://kubernetes.default.svc \
		--dest-namespace sockshop-prod --path onboarding-carts/argo/carts --revision 0.11.0 \
		--sync-policy none

#.PHONY: k8s-apply
#k8s-apply:
#	kubectl get ns cilium-linkerd 1>/dev/null 2>/dev/null || kubectl create ns cilium-linkerd
#	kubectl apply -k k8s/podinfo -n cilium-linkerd
#	kubectl apply -f k8s/client
#	kubectl apply -f k8s/networkpolicy
#
#.PHONY: check-status
#check-status:
#	linkerd top deployment/podinfo --namespace cilium-linkerd
#	linkerd tap deployment/client --namespace cilium-linkerd
#	kubectl exec deploy/client -n cilium-linkerd -c client -- curl -s podinfo:9898
