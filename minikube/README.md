# Haaloft K8S Cluster - minikube (local dev) version

A self-contained Ansible setup that deploys the same services as `../ansible/` (ingress,
cert-manager, Vault, Keycloak, monitoring, Harbor) onto a local [minikube](https://minikube.sigs.k8s.io/)
cluster on this machine, instead of real KVM VMs. Everything needed lives under this
`minikube/` folder - it does not read or write anything under `../ansible/` or the top-level
`../manifests/`.

## Prerequisites

```bash
brew install minikube kubectl helm ansible
brew install --cask docker      # or: brew install --cask podman-desktop
```

Make sure Docker Desktop (or Podman Desktop) is running before you start.

## Quick start

```bash
cd minikube
ansible-playbook site.yml
```

Tag-scoped runs:
```bash
ansible-playbook site.yml --tags cluster        # just start minikube
ansible-playbook site.yml --tags dns            # just (re)configure DNS
ansible-playbook site.yml --tags vault          # just (re)deploy Vault
ansible-playbook site.yml --tags harbor         # just (re)deploy Harbor
```

## Driver

Default driver is `docker` (`group_vars/all.yml: minikube_driver`). Set it to `podman` to use
Podman Desktop instead - no other changes needed.

## DNS

`roles/ingress_dns` enables minikube's `ingress-dns` addon and writes
`/etc/resolver/haaloft.local` so any `*.haaloft.local` hostname resolves to the minikube node
automatically for any Ingress in the cluster.

**Known caveat**: with the `docker`/`podman` driver on macOS, the minikube node's IP is usually
only reachable from the host while `minikube tunnel -p haaloft` is running in a separate
terminal. Start that before testing ingress hostnames. If DNS still doesn't resolve for your
setup, set `hosts_file_fallback: true` in `group_vars/all.yml` and re-run:
```bash
ansible-playbook site.yml --tags dns
```
which manages static entries in `/etc/hosts` instead.

## Services

Toggle optional services in `group_vars/all.yml` under `services:`. Ingress and cert-manager are
always deployed. Defaults: `vault`, `keycloak`, `monitoring`, `harbor` on; `homeassistant`,
`mqtt`, `zigbee2mqtt` off (same convention as `../ansible/`).

## Harbor / pushing images from this Mac

The `harbor` role trusts the cluster's internal CA *inside* the minikube node automatically, so
in-cluster pulls/pushes work out of the box. To push from your Mac's docker/podman CLI, trust the
CA locally too:
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain .haaloft-ca.crt
docker login registry.haaloft.local
docker tag myapp:latest registry.haaloft.local/library/myapp:latest
docker push registry.haaloft.local/library/myapp:latest
```

## Teardown

```bash
ansible-playbook playbooks/teardown.yml
```
Deletes the minikube cluster, removes the `/etc/resolver` entry (and `/etc/hosts` fallback
entries, if used), and cleans up local scratch files (`.vault-credentials`, `.haaloft-ca.crt`,
`.containerd-hosts.toml`).
