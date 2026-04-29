#!/bin/bash

kubectl get vmi -l "az" -ocustom-columns="NAME:.metadata.name,AZ:.metadata.labels.az,IP ADDRS:.status.interfaces[*].ipAddress"

# vms and pods in the same zone (i.e. node) should be able to ping each other
# using both primary and secondary IPs
for az in "az1" "az2"; do
  vmi_name=$(kubectl get vmi -l"az=${az}" -oname | cut -d'/' -f2)
  pod_primary_ip=$(kubectl get po -l"az=${az},app=nginx-${az}" -ojsonpath="{.items[0].metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}" | jq -r '.[] | select(.name=="kindnet").ips[0]')
  pod_secondary_ip=$(kubectl get po -l"az=${az}" -ojsonpath="{.items[0].metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}" | jq -r '.[] | select(.name=="default/bridge-net-ipam").ips[0]')

  echo "${az}: vmi ${vmi_name} ---> pod nginx-${az}"
  echo "* primary IP: ${pod_primary_ip}"
  echo "* secondary IP: ${pod_secondary_ip}"
  kubectl virt ssh fedora@vmi/"${vmi_name}" -i /home/isim/.ssh/id_ecdsa -t="-o PreferredAuthentications=publickey" -t "-o StrictHostKeyChecking=no" -c "ping -c 5 ${pod_primary_ip} && ping -c 5 ${pod_secondary_ip}"
done
