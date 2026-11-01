# Kubernetes Endpoint and ClusterIP Troubleshooting Lab

This folder contains two Bash scripts used to reproduce and diagnose endpoint connectivity problems in a manually installed Kubernetes cluster.

The lab focuses on checking connectivity between pods and comparing direct pod IP, Service ClusterIP, and Service DNS access. It also contains diagnostic logic for kube-apiserver, CoreDNS, pod-to-pod networking, Services, and Endpoints.

## Environment assumptions

The scripts are written for a manually installed Kubernetes cluster running on virtual machines, including control-plane and worker nodes. They expect:

- A Linux control-plane node
- Root or sudo access
- `kubectl` configured for the cluster administrator
- A default namespace containing pods labeled `app=alpine` and `app=nginx`
- An Alpine pod that has `curl` installed
- An Nginx pod listening on TCP port `8080`
- A Service named `nginx-svc` selecting the Nginx pod
- CoreDNS installed in the `kube-system` namespace

The scripts were written for a manually configured cluster hosted in Oracle VirtualBox and may require adaptation for other Kubernetes distributions or CNI plugins.

## Contents

- `clusteripassignementissue.sh` — performs cluster readiness, CoreDNS, pod connectivity, kube-apiserver unit-file, Service, and Endpoint checks from a control-plane node.
- `exec.sh` — tests connectivity from the Alpine pod to Nginx by pod IP, Service ClusterIP, and Service DNS name.

## Important warnings

Review both scripts before running them. They are reproduction and troubleshooting scripts rather than hardened automation:

- `clusteripassignementissue.sh` is intended to run on the control-plane node.
- One function stops `kube-apiserver.service`, attempts to modify `/etc/systemd/system/kube-apiserver.service`, and may change cluster control-plane configuration.
- The scripts can fail or behave unexpectedly because of shell syntax, command output assumptions, pod names, labels, Service names, ports, permissions, or installed tools. Their existing behavior has deliberately been left unchanged.
- Run the scripts only in a disposable test cluster or maintenance window.

## Before running

Create the required test workload if it does not already exist. The examples below assume pod labels and names matching what the scripts expect.

Example labels:

```yaml
metadata:
  labels:
    app: alpine
```

```yaml
metadata:
  labels:
    app: nginx
```

Create or verify the Service:

```bash
kubectl get svc nginx-svc -n default -o wide
kubectl get endpoints nginx-svc -n default
```

Verify that CoreDNS and cluster nodes are healthy:

```bash
kubectl get nodes
kubectl get pods -n kube-system | grep coredns
```

The scripts do not install workloads, CoreDNS, or any missing dependencies.

## Running the scripts

Make the scripts executable if needed:

```bash
cd /path/to/k8s-problems-reproduced/endpointissue
chmod +x clusteripassignementissue.sh exec.sh
```

Run the control-plane-side checks from the Kubernetes control-plane node as root or through a root-capable account:

```bash
sudo ./clusteripassignementissue.sh
```

Run the pod connectivity reproduction from a location with access to the cluster through `kubectl`:

```bash
./exec.sh
```

## Connectivity paths tested by `exec.sh`

The script compares the following paths:

| Test | Destination | Purpose |
|---|---|---|
| Direct pod IP | `http://<nginx-pod-IP>:8080` | Checks whether the CNI can route packets between pods |
| Service ClusterIP | `http://<nginx-service-IP>:8080` | Checks Kubernetes Service routing, including kube-proxy or the CNI dataplane |
| Service DNS | `http://nginx-svc:8080` | Checks DNS resolution and Service connectivity |

Expected interpretation:

- Direct pod connectivity succeeds, but ClusterIP and DNS fail: investigate kube-proxy, the CNI Service dataplane, Endpoints, and the Service selector.
- ClusterIP succeeds, but DNS fails: investigate CoreDNS.
- Direct pod connectivity fails: investigate CNI configuration, NetworkPolicy, routes, firewall rules, and pod network reachability.
- The Endpoint has no addresses: verify the Service selector against the Nginx pod labels and verify pod readiness.

## Manual Kubernetes checks

Useful commands from the control-plane or an administrator workstation include:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get svc -A -n default
kubectl get endpoints -A -n default
kubectl describe svc nginx-svc -n default
kubectl describe endpoints nginx-svc -n default
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

Check pod-to-pod connectivity and DNS from inside the Alpine pod:

```bash
kubectl exec -it pod/<alpine-pod-name> -n default -- ping -c 4 <nginx-pod-IP>
kubectl exec -it pod/<alpine-pod-name> -n default -- curl -v http://<nginx-pod-IP>:8080
kubectl exec -it pod/<alpine-pod-name> -n default -- curl -v http://nginx-svc:8080
```

Resolve the Service manually from the Alpine pod if DNS tools are installed:

```bash
kubectl exec -it pod/<alpine-pod-name> -n default -- nslookup nginx-svc
```

## Troubleshooting notes

### Endpoint remains empty

Check that the Service selector matches the Nginx pod labels and that the Nginx pod is Ready:

```bash
kubectl get pods -n default --show-labels
kubectl describe pod <nginx-pod-name> -n default
kubectl get endpoints nginx-svc -n default -o yaml
```

### CoreDNS is unavailable

Verify that CoreDNS pods are running and that kube-apiserver has the expected cluster DNS and cluster domain configuration:

```bash
kubectl get pods -n kube-system -o wide | grep coredns
systemctl status kube-apiserver.service
```

### `exec.sh` uses port 8080

Both direct pod and Service URL checks use port `8080`. The Service configuration must publish that port unless the script is changed. The script currently targets `nginx-svc:8080` rather than a conventional HTTP Service port.

### Script behavior may differ from intended behavior

Some shell expressions and control flow in these scripts may be invalid or incomplete. Bash diagnostic output, syntax errors, and command-not-found messages should be treated as useful evidence rather than silently worked around. The scripts have been documented without changing their source code.
