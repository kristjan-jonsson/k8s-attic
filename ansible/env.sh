#!/bin/bash
# ============================================================================
# Prompts for sensitive passwords and exports them as environment variables.
# Ansible reads them via {{ lookup('env', 'VAR') }} in group_vars/all.yml.
#
# Usage: source env.sh
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script must be sourced, not executed."
    echo "Usage: source env.sh"
    exit 1
fi

read_secret() {
    local var_name="$1"
    local prompt="$2"
    local current="${!var_name}"

    if [[ -n "$current" ]]; then
        echo "  ${var_name} already set, keeping current value."
        return
    fi

    read -rsp "$prompt" value
    echo ""
    export "$var_name"="$value"
}

echo "=== Haaloft K8S - Environment Setup ==="
echo ""

read_secret HAALOFT_KVM_BECOME_PASS    "KVM host sudo password: "
read_secret HAALOFT_KEYCLOAK_ADMIN_PASS "Keycloak admin password: "
read_secret HAALOFT_KEYCLOAK_PG_PASS    "Keycloak PostgreSQL password: "
read_secret HAALOFT_HARBOR_ADMIN_PASS   "Harbor admin password: "

echo ""
echo "All passwords exported. You can now run:"
echo "  ansible-playbook playbooks/provision-vms.yml"
echo "  ansible-playbook site.yml"
