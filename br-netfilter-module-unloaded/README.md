# Intermittent Kubernetes Service Connectivity: `br_netfilter`

This lab investigates a Kubernetes `ClusterIP` Service that succeeds for some
requests and times out for others. The intended environment is a manually
configured cluster with a control plane and two workers (`node-0` and `node-1`),
a `web` Service, two ready backend pods, and a client pod on each worker.

The folder name describes the working hypothesis, not a diagnosis already
proven in every cluster. Do not claim that `br_netfilter` is the root cause
until the before-change checks and traffic evidence below support it. Record
the actual command output from your cluster in [`ROOT-CAUSE.md`](./ROOT-CAUSE.md)
before making the fix.

> **Lab safety:** The fix changes kernel module and sysctl configuration on
> worker nodes. Use root access and the VM/console or SSH path for recovery.
> Do not restart pods, kubelet, or kube-proxy while collecting initial evidence.

## Problem statement

The reported observations are:

- All application pods are `Running` and `Ready`.
- EndpointSlices contain both backend pod addresses.
- Requests to each backend pod IP work directly.
- Requests to the `web` ClusterIP intermittently time out.
- The result differs when the client pod runs on the other worker.
- Application, kubelet, and kube-proxy logs do not explain the failures.

Those observations narrow the investigation, but they do not prove a specific
cause. A Service request follows a different path from a direct pod-IP request:
it traverses the node's Service dataplane (commonly kube-proxy iptables rules)
before reaching a selected endpoint.

## Hypothesis — record this before changing anything

**Working hypothesis:** one or both workers have inconsistent Linux bridge
netfilter configuration. If `br_netfilter` is unavailable or the bridge
netfilter sysctls are disabled on a worker, bridged pod traffic may not be
handled by the expected netfilter rules. Requests that select an endpoint whose
path crosses the affected node can then fail, while requests selecting another
endpoint succeed. Different client nodes can produce different outcomes
because their routes and Service rules are node-local.

This hypothesis is supported only if the failed Service connections can be
correlated with an affected node or backend path, and the affected node has
missing/inactive bridge-netfilter support or disabled bridge-netfilter sysctls.
If those checks do not match the observed failures, keep investigating routes,
firewall rules, CNI forwarding, conntrack, and endpoint health instead.

**Before any remediation**, capture the hypothesis and the current state from
both workers in `ROOT-CAUSE.md`. Do not load a module or change a sysctl first;
that would destroy useful evidence about the original state.

## Requirements and assumptions

- Administrative `kubectl` access from the jumpbox or control plane.
- Root or `sudo` access to both workers.
- Existing client pods on both workers with `curl` available.
- Existing `web` Service and two ready backend pods.
- `tcpdump`, `conntrack` (if installed), `ip`, `iptables`, `sysctl`, and
  `journalctl` are used only when already available on the nodes.
- Substitute your actual namespaces, pod names, port, interface names, and
  Service IP. The examples use the `default` namespace and TCP port 80.

No commands in this document create or restart workloads, install packages, or
restart Kubernetes components.

## 1. Capture the initial Kubernetes state

Run these from a host with `kubectl` access and save the complete output before
changing either node:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get svc web -n default -o wide
kubectl describe svc web -n default
kubectl get endpointslices -n default \
  -l kubernetes.io/service-name=web -o wide
kubectl get pods -n default --show-labels
```

Confirm that the Service selector matches both ready backend pods, note their
pod IPs and the worker node on which each pod runs, and record the ClusterIP
and Service port. If either endpoint is absent or not ready, resolve that
separately before interpreting this networking test.

## 2. Reproduce and record the ratio

Run the same 20-request test from the existing client pod on **each** worker.
Use a fresh HTTP connection for each request and do not add retries: retries
can hide the failure rate. Replace `<client-pod-node-0>` and
`<client-pod-node-1>` with the actual client pod names.

```bash
kubectl exec -n default <client-pod-node-0> -- sh -c '
success=0
failure=0
i=1
while [ "$i" -le 20 ]; do
  code=$(curl --noproxy "*" -sS --connect-timeout 3 --max-time 5 \
    -H "Connection: close" -o /dev/null -w "%{http_code}" \
    http://<WEB_CLUSTER_IP>:80 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$code" = "200" ]; then
    success=$((success + 1))
    printf "%02d success HTTP %s\n" "$i" "$code"
  else
    failure=$((failure + 1))
    printf "%02d failure curl=%s HTTP=%s\n" "$i" "$rc" "${code:-000}"
  fi
  i=$((i + 1))
done
printf "RESULT success=%s failure=%s total=20\n" "$success" "$failure"
'
```

Run the identical command with `<client-pod-node-1>` and the same ClusterIP.
Record each line and the final totals in `ROOT-CAUSE.md`; do not substitute the
reported “roughly half” for measured results. A timeout is expected to appear
as a nonzero curl status and HTTP code `000`.

If `curl` is not present in the existing client pod, use another existing
client pod that has it. Do not install tools or restart a pod just to run this
test.

## 3. Compare Service and direct-pod paths

From each client pod, run 20 requests to each backend IP directly, using the
same timeout and `Connection: close` settings as above. For example:

```bash
kubectl exec -n default <client-pod-name> -- \
  curl --noproxy '*' -v --connect-timeout 3 --max-time 5 \
  -H 'Connection: close' http://<BACKEND_POD_IP>:80
```

Repeat enough times to check both backends from both client nodes. Record the
backend IP, its worker, client worker, and outcome. This separates Service
selection/NAT from basic pod-IP reachability; a single successful direct
request is not sufficient evidence.

## 4. Identify which Service requests fail

First, if the application response already identifies its backend (for
example, a hostname or pod name), record that value for every request. Do not
change or restart the application merely to add such a response.

Otherwise, observe the worker while repeating the request loop. Start a
capture on the client worker and, if needed, on the worker hosting the suspect
backend. Replace the interface and addresses with values found using `ip
address` and the earlier Kubernetes output:

```bash
sudo tcpdump -ni any -tttt \
  'host <CLIENT_POD_IP> and (host <BACKEND_POD_IP_1> or host <BACKEND_POD_IP_2>) and tcp port 80'
```

Look for a client SYN to a backend followed by a response, versus a SYN or
request with no response before the timeout. Save a short, relevant capture
excerpt or pcap location and timestamps in `ROOT-CAUSE.md`. If `tcpdump` on
the client worker does not show the post-DNAT endpoint, capture on the
destination worker as well; packet visibility depends on the network path and
capture interface.

If `conntrack` is already available, inspect matching connections while the
loop runs:

```bash
sudo conntrack -L -p tcp 2>/dev/null | grep '<WEB_CLUSTER_IP>'
```

The conntrack entry may show the translated backend address. Correlate entries
with request times and source ports; do not infer the failed backend from the
ClusterIP alone. If `conntrack` is unavailable, rely on packet capture and
application/backend identification instead.

Also record the node-local Service rules and routes, without changing them:

```bash
sudo iptables -t nat -nvL KUBE-SERVICES
sudo iptables -t nat -nvL KUBE-SEP-<ENDPOINT_RULE_SUFFIX>
ip route
ip -d link
```

The exact `KUBE-SEP` chain name varies. Find the relevant chains using
`sudo iptables-save -t nat | grep -E 'KUBE-SVC|KUBE-SEP|<WEB_CLUSTER_IP>'`.
If the cluster uses a different kube-proxy mode or firewall backend, record
that instead; do not assume iptables is the active dataplane.

## 5. Check bridge-netfilter state on both workers

Run before remediation on `node-0` **and** `node-1`, and keep the outputs
separate. A missing `lsmod` line alone does not prove that support is absent;
check the module path and sysctl values too.

```bash
uname -r
lsmod | grep '^br_netfilter' || true
test -d /sys/module/br_netfilter && echo 'br_netfilter present' || echo 'br_netfilter absent'
sudo sysctl net.bridge.bridge-nf-call-iptables
sudo sysctl net.bridge.bridge-nf-call-ip6tables
sudo sysctl net.ipv4.ip_forward
ip -d link
sudo iptables -V
```

If a sysctl reports “cannot stat” or “unknown key”, record the exact message.
Compare the values across nodes. For an IPv4 cluster using bridged pod
networking, the expected bridge netfilter setting is
`net.bridge.bridge-nf-call-iptables = 1`; IPv6 bridge traffic may also require
`net.bridge.bridge-nf-call-ip6tables = 1`.

Useful read-only checks for the running kernel and node configuration:

```bash
sudo modprobe -n -v br_netfilter
grep -R --line-number -E 'br_netfilter|bridge-nf-call-(ip|ip6)tables' \
  /etc/modules-load.d /etc/sysctl.d /etc/sysctl.conf 2>/dev/null
```

## 6. State the root cause only when evidence supports it

The intended root-cause layer is the **Linux kernel networking layer**, not
the application or Kubernetes API. The Kubernetes Service is the path that
exposes the problem, but the diagnosis must be backed by node state and packet
evidence.

The `br_netfilter` hypothesis is supported when the collected evidence shows
all of the following:

1. The affected worker is missing `br_netfilter`, or its bridge netfilter
   sysctl is disabled/unavailable, while the other worker has the expected
   state.
2. The failed requests correlate with a backend/forwarding path involving that
   worker; successful requests correlate with a working path.
3. Direct pod-IP requests and endpoint readiness checks succeed as recorded,
   while packets for the failing Service requests show where the request or
   response stops.
4. After the configuration change, the same request tests succeed from both
   client workers without restarting pods, kubelet, or kube-proxy.

If those facts are not observed, do not report `br_netfilter` as proven. Use
the capture to continue into the relevant CNI routes, firewall/forward chains,
conntrack state, or node-specific packet path.

## 7. Apply a persistent fix (only after capturing evidence)

On each affected worker, load the module now if it is available:

```bash
sudo modprobe br_netfilter
```

Persist module loading across reboot:

```bash
echo br_netfilter | sudo tee /etc/modules-load.d/k8s-br-netfilter.conf
```

Persist the bridge sysctls required by an IPv4/IPv6 cluster. For an
IPv4-only cluster, the IPv6 setting may be omitted if IPv6 is not configured:

```bash
sudo tee /etc/sysctl.d/99-k8s-bridge-netfilter.conf >/dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
```

Apply and verify without restarting Kubernetes processes:

```bash
sudo sysctl --system
lsmod | grep '^br_netfilter'
sudo sysctl net.bridge.bridge-nf-call-iptables
sudo sysctl net.bridge.bridge-nf-call-ip6tables
```

If `modprobe` fails because the module is unavailable for the running kernel,
stop here and record the error. Do not claim a persistent fix or reboot the
node until the kernel/module packaging issue has been resolved. These commands
assume the node uses the `iptables` backend and a CNI configuration that
requires bridge netfilter; adapt to the actual cluster configuration.

## 8. Verify the fix and reboot persistence

After applying the change, repeat the exact 20-request Service loop from
clients on **both** workers. The acceptance result is:

```text
node-0 client: success=20 failure=0 total=20
node-1 client: success=20 failure=0 total=20
```

Those lines are the required result, not a result asserted by this document.
Record the actual output, date, and worker in `ROOT-CAUSE.md`. Also repeat the
direct-pod checks and preserve a post-fix capture if it helps show that the
previously failing path now completes.

To establish reboot persistence, reboot one worker at a time during a
maintenance window, allowing the node and workloads to become healthy before
continuing. After each worker reboots:

```bash
lsmod | grep '^br_netfilter'
sudo sysctl net.bridge.bridge-nf-call-iptables
sudo sysctl net.bridge.bridge-nf-call-ip6tables
kubectl get nodes -o wide
kubectl get endpointslices -n default \
  -l kubernetes.io/service-name=web -o wide
```

Then rerun the 20-request loop from each worker. Confirm 20/20 successes from
both locations after the reboot; a successful `sysctl --system` before reboot
alone does not prove persistence.

## Questions answered

Answer these in the final [`ROOT-CAUSE.md`](./ROOT-CAUSE.md), using your
captured results:

1. **Why do only some requests fail?** A ClusterIP selects among endpoints.
   If evidence confirms a broken path to only one backend/node, requests
   selecting that path fail while requests selecting a working path succeed.
   Do not assume a 50/50 endpoint split; selection and connection tracking
   affect the measured ratio.
2. **Why does calling a pod IP directly work?** It bypasses ClusterIP
   endpoint selection and Service DNAT. This helps isolate the Service path,
   but successful direct access alone does not prove the bridge-netfilter
   hypothesis.
3. **Why does the result depend on the client node?** Service rules, routes,
   bridge/module/sysctl state, and packet paths are node-local. The capture
   and per-node state must identify which difference is relevant in this
   cluster.
4. **What should be checked first in production?** Preserve evidence before
   restarting anything: confirm Service and EndpointSlice membership, compare
   direct-pod versus ClusterIP requests from each node, map failed requests
   to backend/node with logs or packet capture, and compare the affected
   nodes' routes, kube-proxy dataplane rules, conntrack, firewall, CNI, and
   `br_netfilter`/sysctl state.

## `ROOT-CAUSE.md` evidence checklist

The report should include:

- Initial hypothesis, written before any changes.
- Baseline Service, EndpointSlice, pod IP, and pod-to-node output.
- The 20-request success/failure ratio from each worker before and after the
  fix.
- Which backend/path each failed request used and the command output or
  packet-capture evidence supporting that conclusion.
- Before/after module and sysctl state on both workers.
- Root-cause layer and answers to the four questions above.
- Exact persistent configuration files/commands and post-reboot verification.

Do not include credentials, private keys, or unrelated packet payloads in the
report. Redact sensitive addresses if the repository is public, while keeping
the evidence sufficient to understand the network path.