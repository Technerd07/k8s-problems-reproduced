#!/bin/bash
#This script must be run on the node machines 
#first check the crictl status of the list of pods that are running on the node machine
#Then first save the iptable rules into a backup file
#make the cni routing blocked which makes the pod to pod conections fail
set -x 
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "Running as root" 
	exec "$0" "$@"
fi
backupfile="$(pwd)/iptable-rules.bak"
destroy_rules (){
	#check wether crictl is running
	if systemctl status crictl.service --no-pager &>/dev/null; then
		echo "crictl return status code:" $?
	fi
#first check the iptable rules and save it to a backupfile
if ! dpkg -l | grep -q iptables ; then
	echo "ERROR: iptables not installed!"
	else 
		apt get update && apt install iptables -y &>/dev/null
fi
#save the rules even if the iptable rules are not present
iptables-save >"${backupfile}"
#now add the route destruction rule into iptables (warning! this rule makes the cni networking fail)
#caution: sudo iptables -A FORWARD -o cni0 -j DROP
iptables -A FORWARD -O cni0 -j DROP 
}
#function to revertback the default routes
revert_back (){
	#copy the backup file to the iptables
	#restore command: sudo iptables -D INPUT -i cni0 -j DROP
	#check the file and copy the content to iptables
	if [ -f "${backupfile}" ]; then
		iptables-restore < "${backupfile}"
		return 0
		else
		 	echo "backupfile not found!"
			return 1
	fi
}
#This function will not be called.. will only be set to call to revert the defaults back to nornmal
main (){
	destroy_rules
}
main "$@"



