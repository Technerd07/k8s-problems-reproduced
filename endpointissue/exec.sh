#!/bin/bash
#RUN this script in the manual cluster for more control
#This script is used to reproduce the issue with exec into a pod that has an endpoint issue in Kubernetes.
#Running this script from the alpine pod to connect to nginx pod via svc (cluster ip) and endpoint(calico-cni-ip) if this fails then the problem has been reproduced successfully.

set -x
set -euo pipefail

if $EUID -ne 0; then
    echo "Running as root"
    exec "$0" "$@"
fi

#first login to alpine pod
alpine_pod=$(kubectl get pods -n default -l app=alpine -o jsonpath='{.items[0].metadata.name}')
nginx_pod=$(kubectl get pods -n default -l app=nginx -o jsonpath='{.items[0].metadata.name}')

nginx_ip=$(kubectl get pod/"${nginx_pod}" -o jsonpath='{.status.podIP}')


#first check the cni connectivity the listening port on the nignx is 8080 and the service port is 80  port-forwarding enabled on the machine
kubectl exec -it pod/"${alpine_pod}" -- curl -s --connect-timeout 5 http://"${nginx_ip}:8080" || echo "Connectivity to nginx pod failed"
#second check the  connectivity to the nginx pod using service name and cluster ip
nginx_service_ip=$(kubectl get svc nginx -n default -o jsonpath='{.spec.clusterIP}')
kubectl exec -it pod/"${alpine_pod}" -- curl -s --connect-timeout 5 http://"${nginx_service_ip}:8080" || echo "connectivity to nginx pod failed over service cluster-IP"
#third now check the connectivity to the nginx pod using service dns name the nginx-svc 
kubectl exec -it pod/"${alpine_pod}" -- curl -s --connect-timeout 5 http://nginx-svc:8080 || echo "connectivity to nginx pod failed over service dns name"

