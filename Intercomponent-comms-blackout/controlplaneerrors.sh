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
	extract_dir="$(pwd)/etcd-${version}-linux-${arch}.tar.gz"
	local downloadurl="https://github.com/etcd-io/etcd/releases/download/${version}/${filename}"
	wget -cv --https-only --limit-rate=10M --timestamping --show-progress "${downloadurl}"
	echo "exit code:" &?
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

main (){
	downloadRelatedArchives
	make_etcdSnapshot
}
main "$@"