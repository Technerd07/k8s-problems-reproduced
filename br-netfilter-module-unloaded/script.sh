#!/bin/bash
#This script is run on the node machine(s) to disable the br_netfilter kernel module
#my cluster run on root by default . elevate previliges to work with kernel stuff
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
    echo "Running as root"
    exec "$0" "$@"
fi
#on the node machine download dependancies
apt update -qq && apt install tcpdump -y
#disable modprobe
#list the br_netfilter details and disable the kernel module
# 2. Disable the iptables bridge call FIRST
echo "[*] Disabling bridge-nf-call-iptables kernel parameter..."
sysctl -w net.bridge.bridge-nf-call-iptables=0

if lsmod | grep "^br_netfilter"; then
     ehco "Disabling kernel module [*]...."
    modprobe -r br_netfilter
fi
echo "[!] Cluster node prepared. Same-node Service routing (Hairpin) is now BROKEN."