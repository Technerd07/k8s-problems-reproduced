#!/bin/bash
#Run this script on the control plane node of the cluster
#This script focuses on backing up etcd snapshots and injecting connection blocking iptable rules for both etcd.service and kube-apiserver.serivce (services) running on their respective ports
#Before executing any thing backing up the etcd snapshots into a file is a must step to move further which in case goes wrong complete cluster state might get into chaos
set -x
set -euo pipefail
if [[ $EUID -ne 0 ]];then
	echo "Running as root"
	exec "$0" "$@"
fi
#First check wether etcdutl binary is installed in the controlplane(node)
#In my case i have not installed but currently when this problem was encountered i went back to jumpbox machine/kubernetes-the-hard-way/Downloads/etcd-xxx.tar.gz/etcdutl and copied it to the controlplane node
downloadRelatedArchives (){
	#first check etcdutl is installed in the system
	if ! command -v etcdutl &>/dev/null; then
		echo "Error: etcdutl is not installed on the system"
		else 
		echo "etcdutl is already installed "
		return 0
	fi
	local arch
	arch=$(dpkg --print-architecture)
	local version="v3.7.3"
	local filename="etcd-${version}"-linux-${arch}.tar.gz
	local extract_dir
	extract_dir="$(pwd)/etcd-${version}-linux-${arch}"
	local downloadurl="https://github.com/etcd-io/etcd/releases/download/${version}/${filename}"
	wget -cv --https-only --limit-rate=10M --timestamping --show-progress "${downloadurl}"
	echo "exit code: $?"
	#now extract the tarball and mv the etcdutl to /usr/local/bin
	tar -xvf "${filename}"
	if [ -d "${extract_dir}" ]; then
		chmod +x "${extract_dir}/etdutl" 
		mv -v "${extract_dir}/etcdutl" /usr/local/bin
		return 0;
		else
			echo "Extracted dir not found at ${extract_dir}"
			return 1
	fi
}
backupfile="/tmp/etcd-backup.db"
make_etcdSnapshot (){
	if ! command -v etcdutl &>/dev/null; then 
		echo "Error: etcdutl binary not found in PATH"
		return 1
	fi
	#Here ill be using the /tmp folder to temporarily store the backup.db file
	etcdutil snapshot save "${backupfile}" 
	#check the stautus of the execution by inspecting the content of the file
	if [[ -f "${backupfile}" ]]; then
		etcdutl snapshot status "${backupfile}" --write-out=table 
		echo "exit status: "$?
		else
			echo "ERROR: file does not exist on the /tmp directory"
			return 1
	fi

}
#now block the traffic and incoming connections over kube-apiserver and etcd and iptable rules of the node
#(warning!):  
# 1. Drop incoming traffic to the API server secure port
#sudo iptables -A INPUT -p tcp --dport 6443 -m comment --comment controlplane-errors-apiserver -j DROP
# 2. Drop incoming traffic to the etcd client port
#sudo iptables -A INPUT -p tcp --dport 2379 -m comment --comment controlplane-errors-etcd -j DROP

#revertback: 
#sudo iptables -D OUTPUT -p tcp --dport 6443 -m comment --comment controlplane-errors-apiserver -j DROP
#sudo iptables -D OUTPUT -p tcp --dport 2379 -m comment --comment controlplane-errors-etcd -j DROP

injecterrors (){
	#check iptables are installed or not
	if ! command -v iptables &>/dev/null; then
		echo "Iptables installed "
		else
		 	echo $?
			apt-get update && apt-get install iptables -y
	fi
	local backupfile="/tmp/iptables.bak"
	#save the rules even if the rules are empty
	iptables-save > "${backupfile}"
	iptables -A INPUT -p tcp --dport 6443 -m comment --comment controlplane-errors-apiserver -j DROP
	iptables -A INPUT -p tcp --dport 2379 -m comment --comment controlplane-errors-etcd -j DROP
	#Now check the tls timedout error from apiserver
	kubectl get pods -A -n default
}
main (){
	downloadRelatedArchives
	make_etcdSnapshot
	injecterrors
}
main "$@"