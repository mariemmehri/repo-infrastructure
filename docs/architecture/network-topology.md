# Network Topology

## Overview

AKS is deployed inside a dedicated VNet for full network control.

---

## Network Diagram

```text
Azure Subscription
└── rg-staging-pfe
    └── vnet-staging-pfe (10.0.0.0/16)
        └── subnet-aks-staging (10.0.1.0/24)
            └── AKS nodes
                ├── argocd namespace
                │   ├── argocd-server
                │   ├── argocd-repo-server
                │   └── argocd-application-controller
                └── app namespace (Sprint 6)
                    └── application pods
```

---

## Address Space

| Resource | CIDR | Purpose |
|---|---|---|
| VNet | 10.0.0.0/16 | Global network space |
| AKS Subnet | 10.0.1.0/24 | Kubernetes nodes |

---

## Why a Dedicated VNet

Without a dedicated VNet:
- AKS uses an auto-managed VNet -> no control
- Cannot add subnets later
- Cannot integrate with other Azure services

With a dedicated VNet:
- Full control over IP ranges
- Can add subnets (monitoring, ingress, etc.)
- Production-grade network isolation

---

## AKS Network Plugin

Default: `kubenet`
- Simple setup
- Nodes get IPs from subnet
- Pods get IPs from internal range

---

## ACR Access

AKS accesses ACR via:
- `AcrPull` role assignment on ACR
- No network rule needed (same subscription)
- No admin credentials needed
