# Haaloft - Home Lab Kubernetes Cluster

A complete Kubernetes home lab running on KVM with RKE2, fully automated with Ansible. Designed for hosting .NET and web-based hobby projects.

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │         Home Network / Router        │
                    │    DNS: *.haaloft.local → node IPs  │
                    └──────────────┬──────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                     │
        ┌─────┴─────┐      ┌─────┴─────┐        ┌─────┴─────┐
        │  rke-01    │      │  rke-02    │        │  rke-03    │
        │  (server)  │      │  (agent)   │        │  (agent)   │
        │  16GB/2CPU │      │  16GB/2CPU │        │  16GB/2CPU │
        │  OL9 / KVM │      │  OL9 / KVM │        │  OL9 / KVM │
        └────────────┘      └────────────┘        └────────────┘
              │                    │                     │
              └────────────────────┼────────────────────┘
                                   │
                          ┌────────┴────────┐
                          │  RKE2 Cluster   │
                          ├─────────────────┤
                          │ NGINX Ingress   │  ← Traffic routing
                          │ Longhorn        │  ← Persistent storage
                          │ cert-manager    │  ← TLS certificates
                          │ Vault           │  ← Secret management
                          │ Keycloak        │  ← Identity / SSO
                          │ Harbor          │  ← Container registry
                          │ ArgoCD          │  ← GitOps deployments
                          │ CoreDNS         │  ← Service discovery
                          └─────────────────┘
```

## Components

| Component        | Purpose                | URL                               |
|-----------------|------------------------|-----------------------------------|
| RKE2            | Kubernetes distribution | -                                 |
| NGINX Ingress   | Reverse proxy / routing | Ports 80/443 on all nodes         |
| Longhorn        | Distributed storage    | https://longhorn.haaloft.local    |
| cert-manager    | TLS certificate mgmt   | -                                 |
| Vault           | Secret management      | https://vault.haaloft.local       |
| Keycloak        | Identity & SSO         | https://auth.haaloft.local        |
| Harbor          | Container registry     | https://registry.haaloft.local    |
| ArgoCD          | GitOps deployments     | https://argocd.haaloft.local      |
| CoreDNS         | Service discovery      | Built into RKE2                   |

## Prerequisites

- RHEL/Oracle Linux KVM host with `libvirt`, `qemu-kvm`, `virt-install`
- Oracle Linux 9 cloud image (`OL9U4_x86_64-kvm-b234.qcow2`)
- Bridge network (`br0`) configured on the KVM host
- Ansible control machine on KVM host

## Quick Start

### 1. Configure variables

Edit [ansible/group_vars/all.yml](ansible/group_vars/all.yml):
- Set your SSH public key
- Set path to the base VM image on the KVM host
- Set the KVM host IP in [ansible/inventory.yml](ansible/inventory.yml)
- Set passwords (or leave defaults and update later via Vault)
- Set your domain if not using `haaloft.local`

### 2. Provision VMs + Deploy (full stack)

```bash
cd ansible

# Create VMs on this host (use -K if your user needs sudo password)
ansible-playbook playbooks/provision-vms.yml -K

# Deploy K8S + all services (SSHes into VMs as rke user)
ansible-playbook site.yml
```

Provisioning and teardown run locally on the KVM host (`connection: local`). VM IPs are discovered automatically via `virsh domifaddr`. The `-K` flag prompts for your sudo password on the KVM host. The `site.yml` playbook SSHes into the VMs as the `rke` user (created by cloud-init with passwordless sudo).

### 3. Teardown and rebuild

```bash
# Destroy everything (VMs, disks, DNS records, local kubeconfig, vault creds)
ansible-playbook playbooks/teardown.yml -K

# Rebuild from scratch
ansible-playbook playbooks/provision-vms.yml -K
ansible-playbook site.yml
```

The teardown playbook asks for confirmation before destroying anything.

### Run specific stages

```bash
# Only RKE2 installation:
ansible-playbook site.yml --tags rke2

# Only services (assumes RKE2 is already running):
ansible-playbook site.yml --tags services

# Only Harbor:
ansible-playbook site.yml --tags harbor

# Re-run base OS config:
ansible-playbook site.yml --tags common
```

### Updates and Kubernetes upgrades

```bash
# OS updates + RKE2 patch releases (e.g. 1.34.1 -> 1.34.3), one node at a time
ansible-playbook playbooks/update-reboot.yml

# Move to the next Kubernetes minor version (e.g. 1.34 -> 1.35), one node at a time
ansible-playbook playbooks/upgrade-rke2.yml -e rke2_target_minor=1.35
```

RKE2 is installed from the `rancher-rke2` dnf repo, which is pinned to one minor
version. `upgrade-rke2.yml` switches that repo to the target minor, upgrades the
server first, then the agents. Minor versions can't be skipped, so go one at a
time, and check the RKE2 release notes first.

### 4. DNS (automatic)

DNS is handled automatically. After VM IP discovery, Ansible registers:
- A records for each node (`rke-01.haaloft.local`, etc.)
- Round-robin A records for services (`registry`, `auth`, `vault`, `longhorn`)
- Wildcard catch-all (`*.haaloft.local` → all nodes)

All records are managed in your BIND server and cleaned up on teardown.
CoreDNS inside the cluster forwards `*.haaloft.local` to BIND so pods can resolve too.

Make sure your clients (dev machine, etc.) use the BIND server for DNS.

### 5. Access the cluster

```bash
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

The kubeconfig is automatically fetched to the project root during deployment.

## Deploying Your Applications

### Push images to Harbor

```bash
# Login to your registry
docker login registry.haaloft.local

# Tag and push
docker tag myapp:latest registry.haaloft.local/library/myapp:latest
docker push registry.haaloft.local/library/myapp:latest
```

### Example .NET App Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-dotnet-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-dotnet-app
  template:
    metadata:
      labels:
        app: my-dotnet-app
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "app-role"
        vault.hashicorp.com/agent-inject-secret-config: "secret/data/apps/my-dotnet-app"
    spec:
      containers:
        - name: app
          image: registry.haaloft.local/library/my-dotnet-app:latest
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: my-dotnet-app
spec:
  selector:
    app: my-dotnet-app
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-dotnet-app
  annotations:
    cert-manager.io/cluster-issuer: haaloft-ca-issuer
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.haaloft.local
      secretName: myapp-tls
  rules:
    - host: myapp.haaloft.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-dotnet-app
                port:
                  number: 80
```

### Using Persistent Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-db-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-db   # 2 replicas, Retain policy
  resources:
    requests:
      storage: 10Gi
```

### Keycloak Integration (.NET)

```json
{
  "Authentication": {
    "Schemes": {
      "OpenIdConnect": {
        "Authority": "https://auth.haaloft.local/realms/haaloft",
        "ClientId": "dotnet-webapp",
        "ClientSecret": "get-from-vault",
        "ResponseType": "code"
      }
    }
  }
}
```

## File Structure

```
k8s-haaloft/
├── README.md
├── .gitignore
├── kubeconfig                          # Auto-generated during deploy
├── virt-install-example                # Original VM creation reference
├── cloud-init/
│   ├── user-data.yaml                  # Cloud-init template (Jinja2)
│   └── meta-data.yaml
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.yml                   # Hypervisor host (VM IPs discovered dynamically)
│   ├── site.yml                        # Master playbook
│   ├── group_vars/
│   │   └── all.yml                     # All configurable variables
│   ├── playbooks/
│   │   ├── provision-vms.yml           # VM creation on KVM host
│   │   ├── provision-vm-single.yml     # Single VM provisioning (included)
│   │   ├── discover-vms.yml            # DHCP IP discovery from hypervisor
│   │   ├── update-reboot.yml           # Rolling OS + RKE2 patch updates
│   │   ├── upgrade-rke2.yml            # Rolling Kubernetes minor upgrade
│   │   ├── teardown.yml                # Destroy everything (VMs + DNS)
│   │   └── teardown-vm-single.yml      # Single VM teardown (included)
│   └── roles/
│       ├── common/                     # Base OS: modules, sysctl, swap, SELinux
│       ├── rke2_server/                # RKE2 control plane
│       ├── rke2_agent/                 # RKE2 workers
│       ├── helm/                       # Helm + chart repos
│       ├── dns/                        # BIND zone management
│       │   ├── tasks/
│       │   │   ├── main.yml            # Create/update zone
│       │   │   └── cleanup.yml         # Remove zone (teardown)
│       │   └── templates/
│       │       └── zone-forward.j2     # Zone file template
│       ├── cluster_services/           # cert-manager, Longhorn, Vault, Keycloak
│       │   ├── tasks/
│       │   │   ├── main.yml
│       │   │   ├── ingress.yml
│       │   │   ├── cert_manager.yml
│       │   │   ├── longhorn.yml
│       │   │   ├── vault.yml
│       │   │   ├── keycloak.yml
│       │   │   └── coredns.yml
│       │   └── templates/
│       │       └── coredns-custom.yaml.j2
│       └── harbor/                     # Container registry
└── manifests/
    ├── ingress/
    │   ├── nginx-config.yaml
    │   └── example-ingress.yaml
    ├── storage/
    │   ├── longhorn-values.yaml
    │   └── storage-classes.yaml
    ├── keycloak/
    │   ├── namespace.yaml
    │   ├── keycloak-values.yaml
    │   └── keycloak-realm-example.yaml
    ├── vault/
    │   └── vault-values.yaml
    ├── harbor/
    │   └── harbor-values.yaml
    └── cert-manager/
        ├── cert-manager-values.yaml
        └── cluster-issuers.yaml
```

## Customization Checklist

Before deploying, update these in [ansible/group_vars/all.yml](ansible/group_vars/all.yml):

- [ ] `ssh_public_key` - Your SSH public key
- [ ] `vm_base_image` - Path to OL9 qcow2 image on this host
- [ ] DNS server IP in `inventory.yml` and `dns_server_ip` in `group_vars/all.yml`
- [ ] `acme_email` - Your email for Let's Encrypt (if using)
- [ ] `keycloak_admin_password` / `keycloak_pg_password`
- [ ] `harbor_admin_password`
- [ ] Domain name if not using `haaloft.local`
