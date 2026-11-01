#!/bin/bash
#This script must be run on the manual cluster
#Dns name resoultion error when pods try to access the service (nginx-svc) via domain name -> (nginx-svc)
#problem: The cluster works fine , POD-POD comms work fine over cni (calico) the service is reachable but when tried the cluster ip or the dns name of the service the 
#requests gets dropped to null nothing returns back.. similarly the host-only network becomes default route on the node-1 making the internet un accessable 
#Kubernetes supplies pod resolver settings through the pod configuration and kubelet.

set -x 
set -euo pipefail

#nameserver 10.96.0.10 (cluster-IP configured by kube-apiserver unit file change)
#search default.svc.cluster.local svc.cluster.local cluster.local ec2.internal (Delete this line)
#options ndots:5 (no changes)

#Show the workloads and Service endpoints used by this reproduction.
kubectl get pods -n default
kubectl get svc -n default
kubectl get endpoints -n default

delete_configlinesOn_resolvconf (){
    local alpine_pod nginx_pod
    alpine_pod="$(kubectl get pods -n default -l app=alpine -o jsonpath='{.items[0].metadata.name}')"
    nginx_pod="$(kubectl get pods -n default -l app=nginx -o jsonpath='{.items[0].metadata.name}')"

    if [[ -z "$alpine_pod" ]]; then
        echo "No pod found with label app=alpine in namespace default" >&2
        return 1
    fi
    if [[ -z "$nginx_pod" ]]; then
        echo "No pod found with label app=nginx in namespace default" >&2
        return 1
    fi

    # Port-forward the Nginx pod separately if needed for comparison:
    # kubectl port-forward -n default "pod/$nginx_pod" 8080:80
    # Inspect DNS and attempt Service access from the Alpine pod.
    kubectl exec "pod/$alpine_pod" -- sh -c '
        curl -v http://nginx-svc:8080
        echo "Current resolver configuration:"
        cat /etc/resolv.conf
        echo "Search domains containing svc.cluster.local:"
        grep "svc.cluster.local" /etc/resolv.conf || true
    '
    #if the curl command gets stuck on the resolution the problem has been raised successfully on the alpine pod
}
main (){
    delete_configlinesOn_resolvconf
}

main "$@"
