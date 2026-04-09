ARCH := $(shell uname -m)
ifeq ($(ARCH),x86_64)
	ARCH = amd64
else ifeq ($(ARCH),aarch64)
	ARCH = arm64
else
	$(error "Unsupported architecture: $(ARCH)")
endif

# all targets that depend on kubectl should be listed here
KUBE_TARGETS := kubevirt fedora multus
$(KUBE_TARGETS): $(KUBECTL)

# all targets that depend on kind should be listed here
KIND_TARGETS := cluster purge
$(KIND_TARGETS): $(KIND)

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

cluster:
	$(KIND) create cluster --name dev --config=./kind.yaml

kubevirt:
	VERSION=$$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt) ;\
	$(KUBECTL) create -f "https://github.com/kubevirt/kubevirt/releases/download/$${VERSION}/kubevirt-operator.yaml" ;\
	$(KUBECTL) create -f "https://github.com/kubevirt/kubevirt/releases/download/$${VERSION}/kubevirt-cr.yaml"
	$(KUBECTL) -n kubevirt wait --for condition=Ready po -lkubevirt.io=virt-operator
	$(KUBECTL) -n kubevirt wait --for condition=Ready po -lapp.kubernetes.io/component=kubevirt

multus:
	$(KUBECTL) apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
	$(KUBECTL) -n kube-system wait --for condition=Ready po -lapp=multus

workloads:
	$(KUBECTL) delete vm fedora --ignore-not-found --wait
	$(KUBECTL) delete secret generic fedora-cloudinit --ignore-not-found --wait
	$(KUBECTL) create secret generic fedora-cloudinit --from-file=userdata=./cloudinit
	$(KUBECTL) apply -f fedora.yaml
	$(KUBECTL) virt start fedora
	$(KUBECTL) apply -f nginx.yaml

purge:
	$(KIND) delete cluster --name dev
