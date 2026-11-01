#!/bin/bash
#This script must be run on the node machine


set -x
set -euo pipefail

if $EUID -ne 0; then
    echo "Running as root"
    exec "$0" "$@"
fi
check_routing (){
    local defaultRoute=$(ip route show | grep -q "^default" | grep "enp0s8" || true);

    if [ -z "${defaultRoute}" ]; then
        echo "[-] No default route found!"
        return 1;
    fi
    #now parse the defaultRoute variable and then validate the commands
    bad_gateway=$(echo "${defaultRoute}" | awk '{print $3}');

    echo "Deleting the bad-gateway"
    ip route del via "${bad_gateway}" dev enp0s8
}
 main (){
    check_routing
}