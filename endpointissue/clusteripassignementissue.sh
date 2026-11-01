#!/bin/bash
#run this script as a root user . my environment = manually installed kubernetes cluster on windows machine
#running over oracle virtual box vm's
#This script must be run on the controlplane node which has kube-apiserver component is running

set -euo pipefail
set -x

if $EUID -ne 0; then
    echo "Running as a root user"
    exec sudo "$0" "$@"
fi

#first check the basic cluster is online and all nodes are ready
nodesReady=$(kubectl get nodes -A -n kube-system | grep -c "Ready")
if [ "${nodesReady}" -eq 0 ]; then
    echo "Cluster is not ready. please check the cluster status "
    exit 1; 
fi
#check core-dns pod* s
bool istrue=$(kubectl get pods -A -n kube-system | grep -c "coredns" &>/dev/null)
if [ "${istrue}" == 0 ]; then
    echo "Core-dns pods are  running "
    exit 0;
fi

#check pods that are running inside the kube-system namespace
#for testing im using nignx pod and alpine pod with curl installed to check the connectivity between the pods and the clusterip service
#first check these pods are running
podsrunning=$(kubectl get pods -A -n default | grep -c "alpine" "nginx")
#first check the ipof the pods and store them into a variable
ipvarnginx=$(kubectl exec -it pods/nginx -n default -- hostname -I | awk '{print $1}')
ipvaralpine=$(kubectl exec -it pods/alpine -n default -- hostname -I | awk '{print $1}')
#check the connectivity between the pods and the clusterip service

check_podtopodcomm (){
    #first check the connectivity from alpine pod to nginx
    #pod to pod connectivity check if cni calico is working fine or not
    returnStatus= $(kubectl exec -it pod/alpine -n default -- ping -c 4 "${ipvarnginx}" 2&1> /dev/null; echo $?)
    while returnStatus -eq 0; do
        echo "Connectivity between alpine pod and nginx pod is successful"
        return 0;
    done
}
check_kubeapiserverUnitFile (){
    if [ "$(systemctl status kube-apiserver.service 2>/dev/null | grep -c "Active: active (running)")" -gt 0 ]; then
        echo $?;
        #first stop the service and check the unit file wether it has --cluster-dns flag and ip assignment subnet or not inside
        systemctl stop kube-apiserver.service          
        filecontainsclusterDns=$(cat /etc/systemd/system/kube-apiserver.service | grep -c "--cluster-DNS" "--cluster-domain")

       #This makes the api server to assign coredns pods IP from the cluster dns subnet range
       #In the manual installation there is no in built core-dns pods that run automatically these pods must be installed manually from the reo coredns/deployment/kubernetes/deploy.sh file
       #in order to install the coredns pod fetch this file and edit the yaml manifest to change the attributes and replica sets on basis of your compute resources.

        while "True"; do
            if [ "${filecontainsclusterDns}" -gt 0 ]; then
                echo "True : The kube-apiserver unit file contains the --cluster-dns flag and the ip assignment subnet deleting the lines [*]...."
                #delete those lines from the unit file and start the service and check the logs for any errors
                sed -i '/--clusterDNS=/d' /etc/systemd/system/kube-apiserver.service
                sed -i '/--cluster-domain=/d' /etc/systemd/system/kube-apiserver.service
                return 0;
                else 
                echo "False"
            fi
        done
    fi
}
check_endpointassignment (){
    #check endpoints and svcs on the cluster
    kubectl get endpoints -A -n default
    kubectl get svc -A -n default
    #check if the ednpoint field says <none> flag
    if [ "$(kubectl get endpoints -A -n default | grep -c "<none>")" -gt 0 ]; then
        echo  "Endpoint assignment failure detected. Please check the clusterip assignment issue"
        return 1;
    fi
}

main (){
}
main "$@"
