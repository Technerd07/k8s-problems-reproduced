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
	declare arch=$(dpkg --print-architecture)
	dir=etcd-v3.7.3-linux-"${arch}".tar.gz 
	wget -cv --https-only --limit-rate=10M --timestamping --show-progress https://github.com/etcd-io/etcd/releases/download/v3.7.3/etcd-v3.7.3-linux-"${arch}".tar.gz
	echo "exit code:" &?
	#now extract the tarball and mv the etcdutl to /usr/local/bin
	tar -xvf etcd-v3.7.3-linux-"${arch}".tar.gz
	if [ -d "${dir}" ]; then
		chmod +x "${dir}/etdutl" 
		mv -v "${dir}/etcdutl" /usr/local/bin
		return 0;
		else
			echo "Dir not found"
			return 1
	fi

}

main (){
	downloadRelatedArchives
}
main "$@"