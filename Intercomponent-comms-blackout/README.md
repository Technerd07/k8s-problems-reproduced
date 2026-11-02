# Intercomponent Communications Blackout

This exercise demonstrates a staged Kubernetes outage by disrupting pod-to-pod networking first, then disrupting the control plane's access to etcd and the Kubernetes API server.

> **Use only in a disposable lab cluster.** These steps can make workloads unreachable and prevent normal cluster administration. Keep out-of-band access to every affected node and make sure you can use SSH or a VM/console session even when Kubernetes is unavailable.

## Intended failure sequence

1. On a node, `blockcniroutingonnode.sh` saves the current iptables rules to `iptable-rules.bak` in the current working directory.
2. It appends `-A FORWARD -o cni0 -j DROP`. This drops forwarded packets leaving `cni0`, which is intended to disrupt pod-to-pod communication.
3. On the control-plane node, the intended next step is to take and verify an etcd snapshot.
4. After the snapshot is safely stored, the intended fault injection blocks traffic to etcd's client port (commonly TCP 2379).
5. The final intended step blocks access to the Kubernetes API server (commonly TCP 6443), causing `kubectl` and other API clients to fail.

```mermaid
    A([Healthy cluster]) --> B

    subgraph NETWORK[STAGE 1 — POD NETWORK]
        direction LR
        B[Save firewall rules<br/>on the node] --> C[DROP forwarded traffic<br/>leaving cni0] --> D([POD-TO-POD<br/>COMMUNICATION FAILS])
    end

    D --> E

    subgraph CONTROL[STAGE 2 — CONTROL PLANE]
        direction LR
        E[Take and verify<br/>etcd snapshot] --> F[Block etcd client traffic<br/>TCP port 2379] --> G[Block API server traffic<br/>TCP port 6443] --> H([CLUSTER API<br/>BECOMES UNAVAILABLE])
    end

    classDef start fill:#ecfdf5,stroke:#059669,color:#064e3b,stroke-width:3px,font-size:20px
    classDef action fill:#eff6ff,stroke:#2563eb,color:#172554,stroke-width:2px,font-size:18px
    classDef failure fill:#fff1f2,stroke:#e11d48,color:#881337,stroke-width:3px,font-size:19px
    class A start
    class B,C,E,F,G action
    class D,H failure

    style NETWORK fill:#f8fafc,stroke:#64748b,stroke-width:2px
    style CONTROL fill:#f8fafc,stroke:#64748b,stroke-width:2px
```

## Current script status

`blockcniroutingonnode.sh` currently implements the first firewall change and saves a full ruleset backup. Its `revert_back` function exists, but `main` does not provide a way to call it; the script always runs `destroy_rules`.

`controlplaneerrors.sh` is still a draft. It currently does **not** take an etcd snapshot or add rules for etcd or kube-apiserver. Its download/install function also has unfinished and invalid commands. Do not rely on it to perform the control-plane stages until it has been completed and reviewed.

Check actual interface names, etcd endpoints, certificates, and ports in your cluster configuration before adapting the exercise. Kubernetes distributions and CNI plugins can use different interfaces and firewall backends.

## Recovery: return the cluster to normal

Perform recovery through node/VM console or SSH so it does not depend on the Kubernetes API.

1. **Remove the injected control-plane rules first.** Use the exact matching `iptables -D` commands for the etcd and API rules you added. For example, if the rules were inserted into `INPUT` with these exact match fields:

   ```bash
   sudo iptables -D INPUT -p tcp --dport 6443 -m comment --comment controlplane-errors-apiserver -j DROP
   sudo iptables -D INPUT -p tcp --dport 2379 -m comment --comment controlplane-errors-etcd -j DROP
   ```

   Adjust the chain, direction, interface, ports, and comment to exactly match your actual rules. If rules were added more than once, delete each matching copy. Do not flush all iptables chains as a shortcut.

2. **Restore the CNI-node ruleset backup.** On each node where the CNI block was applied, locate the backup created from the same working directory used to run the script, then restore it:

   ```bash
   sudo iptables-restore < /path/to/iptable-rules.bak
   ```

   `iptables-restore` restores the saved full ruleset, so use the backup from that node and from immediately before this exercise. It can overwrite firewall changes made after the backup. If the backup is missing or stale, remove only the injected rule instead:

   ```bash
   sudo iptables -D FORWARD -o cni0 -j DROP
   ```

3. **Confirm connectivity and service health.** Check node and pod connectivity, then verify etcd, kube-apiserver, and node agents using the service/runtime tooling configured for the cluster. Once the API is responding, verify with `kubectl get nodes` and inspect affected workloads.

4. **Use the etcd snapshot only if etcd data recovery is needed.** A firewall-induced etcd outage normally calls for removing the block and restoring connectivity, not restoring an older snapshot. Snapshot restoration is a separate disaster-recovery operation; follow the etcd version and topology-specific procedure for your cluster.

## Notes

- The node script uses `cni0` as a fixed interface and `iptables` as its firewall tool. Confirm both match the lab.
- Keep the snapshot and firewall backups off the affected control-plane node as well if the lab is intended to cover node loss.
- Record the exact rules added during fault injection so they can be removed precisely during recovery.
