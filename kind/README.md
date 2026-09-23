# Haaloft K8S Cluster - kind (local dev) version

A self-contained Ansible setup that deploys the same services as `../ansible/` (ingress,
cert-manager, Vault, Keycloak, monitoring, Harbor) onto a local [kind](https://kind.sigs.k8s.io/)
cluster running under Podman (or Docker) on this machine, instead of real KVM VMs. Everything
needed lives under this `kind/` folder - it does not read or write anything under `../ansible/`
or the top-level `../manifests/`.

This automation does **not** create or manage the kind cluster's lifecycle - it assumes one
already exists, and only deploys services onto it. That matches how this was actually used:
against an existing `kind-cluster` cluster running under Podman Desktop.

## Prerequisites

```bash
brew install kind kubectl helm ansible
```

Podman Desktop (or Docker Desktop) running, and `podman`/`docker` on your `PATH`.

## Create the kind cluster (if you don't already have one)

Ingress needs a node labeled `ingress-ready=true` and host ports mapped for 80/443. Example
`kind` config (adjust the host ports if 80/443 are already taken on your Mac - the vars below
assume 9090/9443):

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 9090
        protocol: TCP
      - containerPort: 443
        hostPort: 9443
        protocol: TCP
```
```bash
kind create cluster --name kind-cluster --config kind-config.yaml
```

If you already have a cluster whose name, container engine, or port mappings differ from the
defaults, update `group_vars/all.yml` (`kind_cluster_name`, `kind_container_engine`,
`ingress_http_port`, `ingress_https_port`) to match - check actual port mappings with
`podman ps` / `docker ps`.

## Corporate network TLS interception (optional)

If your network terminates outbound HTTPS through a TLS-decrypt proxy, image pulls from
inside the kind node may fail with "certificate signed by unknown authority". If the
proxy's root CA is already trusted on your Mac (e.g. via Jamf/MDM), copy `.env.example`
to `.env`, set `CORPORATE_CA_KEYCHAIN_LABELS` to its macOS Keychain label(s), and source
it before running ansible-playbook:
```bash
cp .env.example .env   # then edit .env
set -a && source .env && set +a
```
Leave it unset on a non-corporate network - `.env` is git-ignored so this never gets
committed.

## Quick start

```bash
cd kind
ansible-playbook site.yml
```

Tag-scoped runs:
```bash
ansible-playbook site.yml --tags dns             # just (re)configure /etc/hosts
ansible-playbook site.yml --tags vault           # just (re)deploy Vault
ansible-playbook site.yml --tags harbor          # just (re)deploy Harbor
```

## DNS and ports

`roles/hosts_dns` manages static `/etc/hosts` entries pointing `*.haaloft.local` at `127.0.0.1`.
kind's ingress is reached through the host ports mapped when the cluster was created
(`ingress_http_port`/`ingress_https_port` in `group_vars/all.yml`, default `9090`/`9443`) -
**not** 80/443 - so include the port in every URL, e.g. `https://vault.haaloft.local:9443`.

## Services

Toggle optional services in `group_vars/all.yml` under `services:`. Ingress and cert-manager are
always deployed. Defaults: `vault`, `keycloak`, `monitoring`, `harbor` on; `homeassistant`,
`mqtt`, `zigbee2mqtt` off (same convention as `../ansible/`).

The `ingress` step also removes any stray `projectcontour` namespace before installing
ingress-nginx, in case a different ingress controller was tried previously - all manifests here
assume `ingressClassName: nginx`.

## Harbor / pushing images from this Mac

The `harbor` role trusts the cluster's internal CA *inside the kind node container* automatically
(via `podman exec`/`docker exec`, no SSH needed) and configures a containerd registry mirror
there, so in-cluster pulls/pushes work out of the box. To push from your Mac's docker/podman CLI,
trust the CA locally too:
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain .haaloft-ca.crt
docker login registry.haaloft.local:9443
docker tag myapp:latest registry.haaloft.local:9443/library/myapp:latest
docker push registry.haaloft.local:9443/library/myapp:latest
```

## Teardown

```bash
ansible-playbook playbooks/teardown.yml
```
Uninstalls all services this automation deployed (Helm releases + namespaces) and removes the
`/etc/hosts` entries and local scratch files (`.vault-credentials`, `.haaloft-ca.crt`,
`.containerd-hosts.toml`, `.containerd-registry-config-path.toml`). The kind cluster itself is
left running - remove it yourself with `kind delete cluster --name kind-cluster` if you want that
too.
