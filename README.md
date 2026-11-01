# Kubernetes Problems Reproduced

This repository documents hands-on work with a Kubernetes cluster that I installed and configured manually. It records problems I encountered while building and operating the cluster, along with the steps I used to investigate, reproduce, debug, and resolve them.

The work is practical and experimental: I explore how the cluster behaves, use shell scripts and command-line tools to inspect and reproduce issues, and document what I learn from fixing them. The scenarios may cover different parts of Kubernetes and its surrounding environment, including networking, DNS, Services, and node configuration.

This repository is intended as a personal learning record and a practical reference for understanding real cluster behavior. The scripts and instructions reflect the specific environments in which the issues were encountered, so they may need review and adaptation before being used elsewhere. They are not intended as production-ready automation.

## Environment

The manual cluster is hosted on my laptop, with a 13th-generation Intel Core i5 processor, 16 GB of RAM, and a 1 TB SSD. It consists of one cluster with two Kubernetes nodes. Each node runs two pods in the scenarios documented here.

The cluster is built from Linux virtual machines with these allocations:

| Virtual machine | Role | Memory | Storage |
|---|---|---:|---:|
| `jumpboxmachine` | Jump box | 1 GB | 10 GB |
| `controlplane` | Kubernetes control plane | 2 GB | 20 GB |
| `node-0` | Kubernetes worker node | 1 GB | 10 GB |
| `node-1` | Kubernetes worker node | 1 GB | 10 GB |

Two network interfaces are configured on the VMs:

- `enp0s8` uses a manually configured VirtualBox host-only network on `192.158.56.1/24` for cluster-wide communication.
- `enp0s3` uses VirtualBox NAT (shown here as “VNAT”) to provide shared internet access.

These details describe my lab setup. Other scenarios may use different VM allocations, interface names, addresses, or network settings.
