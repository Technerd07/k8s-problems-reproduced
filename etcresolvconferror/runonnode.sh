#!/bin/bash
#This script must be run on the node machine


set -x
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Running as root"
    exec "$0" "$@"
fi
#example: default via 10.0.2.2 dev enp0s3 proto dhcp metric 100
check_routing (){
    local defaultRoute
    defaultRoute=$(ip route show | grep  "^default" | grep "enp0s8" || true);
    badGateway=$(echo "${defaultRoute}" | awk '{print $3}')
    device=$(echo "${defaultRoute}" | awk '{print $5}')

    ip route add default via "${badGateway}" dev "${device}"
    #The below lines are used for if the dns resolution server is already correct but in our case we need to go opposite we need to add the problem to the solution
    #now parse the defaultRoute variable and then validate the commands
    #bad_gateway=$(echo "${defaultRoute}" | awk '{print $3}');
    #echo "Deleting the bad-gateway"
    #ip route del via "${bad_gateway}" dev enp0s8
}
#nameserver 10.96.0.10 (cluster-IP configured by kube-apiserver unit file change)
#search default.svc.cluster.local svc.cluster.local cluster.local ec2.internal (Delete this line)
#options ndots:5 (no changes)
main (){
    check_routing
}