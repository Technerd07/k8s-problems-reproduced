#!/bin/bash
#This script must be run on the manual cluster
#Dns name resoultion error when pods try to access the service (nginx-svc) via domain name -> (nginx-svc)

set -x 
set -euo pipefail
if $EUID -ne 0; then
    echo "Running as root"
    exec "$0" "$@"
fi
#problem: The cluster works fine , POD-POD comms work fine over cni (calico) the service is reachable but when tried the cluster ip or the dns name of the service the 
#requests gets dropped to null nothing returns back.. similarly the host-only network becomes default route on the node-1 making the internet un accessable 

