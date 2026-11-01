#!/bin/bash
#This script must be run on the manual cluster
#Dns name resoultion error when pods try to access the service (nginx-svc) via domain name -> (nginx-svc)
#problem: The cluster works fine , POD-POD comms work fine over cni (calico) the service is reachable but when tried the cluster ip or the dns name of the service the 
#requests gets dropped to null nothing returns back.. similarly the host-only network becomes default route on the node-1 making the internet un accessable 
#solution: The dns server tags are added in dynamic time with the pods by the kubelet.service running on the node machine
#server svc.cluster.local cluster.local etc are the lines that define the route to dns server (core-dnspod)
set -x 
set -euo pipefail
if $EUID -ne 0; then
    echo "Running as root"
    exec "$0" "$@"
fi

#

