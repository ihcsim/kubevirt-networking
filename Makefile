ARCH := $(shell uname -m)
ifeq ($(ARCH),x86_64)
	ARCH = amd64
else ifeq ($(ARCH),aarch64)
	ARCH = arm64
else
	$(error "Unsupported architecture: $(ARCH)")
endif

# all targets that depend on kubectl should be listed here
KUBE_TARGETS := cluster kubevirt multus nad cloudconfig base host-bridge
$(KUBE_TARGETS): $(KUBECTL)

# all targets that depend on kind should be listed here
KIND_TARGETS := cluster purge
$(KIND_TARGETS): $(KIND)

# all targets that depend on docker should be listed here
DOCKER_TARGETS := containerdisk
$(DOCKER_TARGETS): $(DOCKER)

KUBECTL ?= kubectl
$(KUBECTL):
	@which $(KUBECTL) > /dev/null || ( \
		echo "kubectl not found, downloading..." && \
		curl -sSLO https://dl.k8s.io/release/$$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(ARCH)/kubectl && \
		chmod +x kubectl \
	)

KIND ?= kind
KIND_VERSION ?= v0.31.0
$(KIND):
	@which $(KIND) > /dev/null || ( \
		echo "kind not found, downloading..." && \
		curl -Lo ./kind https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-linux-$(ARCH) && \
		chmod +x ./kind && \
		sudo mv ./kind /usr/local/bin/kind \
	)

DOCKER ?= docker
$(DOCKER):
	@which $(KIND) > /dev/null || ( \
		echo "docker not found, see https://docs.docker.com/engine/install/ for installation instructions..." && \
		exit 1
	)

cluster:
	$(KIND) create cluster --name dev --config=./yaml/kind.yaml
	$(KUBECTL) label node dev-worker topology.kubernetes.io/zone=az1
	$(KUBECTL) label node dev-worker2 topology.kubernetes.io/zone=az2

kubevirt:
	VERSION=$$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt) ;\
	$(KUBECTL) create -f "https://github.com/kubevirt/kubevirt/releases/download/$${VERSION}/kubevirt-operator.yaml" ;\
	$(KUBECTL) create -f "https://github.com/kubevirt/kubevirt/releases/download/$${VERSION}/kubevirt-cr.yaml"
	$(KUBECTL) -n kubevirt wait --for condition=Ready po -lkubevirt.io=virt-operator --timeout=5m
	sleep 120
	$(KUBECTL) -n kubevirt wait --for condition=Ready po -lapp.kubernetes.io/component=kubevirt --timeout=5m

multus:
	$(KUBECTL) apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
	$(KUBECTL) -n kube-system wait --for condition=Ready po -lapp=multus

nad:
	$(KUBECTL) apply -f ./yaml/nad

workloads: cloudconfig base host-bridge

base:
	$(KUBECTL) delete -Rf ./yaml/base --ignore-not-found --wait
	$(KUBECTL) apply -Rf ./yaml/base

host-bridge:
	$(KUBECTL) delete secret netconfig-host-bridge --ignore-not-found --wait
	$(KUBECTL) create secret generic netconfig-host-bridge --from-file=networkdata=./yaml/host-bridge/ipam-local/netconfig
	$(KUBECTL) delete secret netconfig-stat0 --ignore-not-found --wait
	$(KUBECTL) create secret generic netconfig-stat0 --from-file=networkdata=./yaml/host-bridge/static/netconfig-stat0
	$(KUBECTL) delete secret netconfig-stat1 --ignore-not-found --wait
	$(KUBECTL) create secret generic netconfig-stat1 --from-file=networkdata=./yaml/host-bridge/static/netconfig-stat1
	$(KUBECTL) delete -Rf ./yaml/host-bridge --ignore-not-found --wait
	$(KUBECTL) apply -Rf ./yaml/host-bridge

cloudconfig:
	$(KUBECTL) delete secret cloudinit --ignore-not-found --wait
	$(KUBECTL) create secret generic cloudinit --from-file=userdata=./cloudinit

validate:
	./validate.sh

.PHONY: containerdisk
containerdisk:
	$(DOCKER) build -t isim/ubuntu-containerdisk:latest ./containerdisk
	$(DOCKER) push isim/ubuntu-containerdisk:latest

purge:
	$(KIND) delete cluster --name dev
