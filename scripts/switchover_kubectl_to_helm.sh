#!/usr/bin/env bash

set -euo pipefail

# Switchover script: kubectl-managed Cilium + hcloud CCM -> Helm-managed
#
# What it does (in order):
# 1) Validates tools and context, asks for confirmation (or --yes)
# 2) Backs up Terraform state to ./tfstate-backup-<timestamp>.json
# 3) Removes kubectl_* items for Cilium/CCM from Terraform state
# 4) Deletes legacy Cilium/CCM resources from the cluster
# 5) Runs `terraform apply` to install Helm releases from your current config
# 6) Waits for rollouts and prints status
#
# Notes:
# - Run this from the Terraform ROOT that calls your module (default is CWD).
# - If your module address is NOT `module.talos`, pass --module-addr accordingly.
# - Expect a brief dataplane disruption during Cilium switchover. Use a maintenance window.

ROOT_DIR="$(pwd)"
MODULE_ADDR="module.talos"
ASSUME_YES=false

usage() {
  cat <<EOF
Usage: $0 [--root-dir <path>] [--module-addr <addr>] [--yes]

Options:
  --root-dir <path>     Terraform root dir that uses the module (default: current dir)
  --module-addr <addr>  Module address for the resources (default: module.talos)
  --yes                 Skip confirmation prompt

Example:
  $0 --root-dir /path/to/cluster/live --module-addr module.network.talos --yes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-dir)
      ROOT_DIR="$2"; shift 2;;
    --module-addr)
      MODULE_ADDR="$2"; shift 2;;
    --yes)
      ASSUME_YES=true; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

need_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required binary: $1" >&2; exit 1; }
}

confirm() {
  if $ASSUME_YES; then return 0; fi
  echo "WARNING: This will remove existing Cilium and hcloud CCM resources and reinstall via Helm."
  echo "A brief dataplane disruption is expected. Ensure this is a maintenance window."
  read -r -p "Proceed? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted."; exit 1; }
}

backup_state() {
  local ts
  ts="$(date +%F-%H%M%S)"
  echo "Backing up Terraform state -> ./tfstate-backup-$ts.json"
  terraform state pull > "tfstate-backup-$ts.json"
}

state_rm_if_present() {
  # Reads addresses on stdin and runs terraform state rm for those present in state list
  local addr
  local all
  all="$(terraform state list || true)"
  while IFS= read -r addr; do
    [[ -z "$addr" ]] && continue
    if echo "$all" | grep -Fxq "$addr"; then
      echo "terraform state rm $addr"
      terraform state rm "$addr"
    else
      echo "(skip) not in state: $addr"
    fi
  done
}

remove_kubectl_items_from_state() {
  echo "Removing kubectl_* resources from Terraform state (non-destructive)..."
  terraform state list \
    | grep -E "^${MODULE_ADDR}\.kubectl_manifest\.apply_" || true

  # Remove kubectl_manifest.apply_* entries
  terraform state list \
    | grep -E "^${MODULE_ADDR}\.kubectl_manifest\.apply_" \
    | state_rm_if_present

  # Remove kubectl_file_documents data sources
  terraform state list \
    | grep -E "^${MODULE_ADDR}\.data\.kubectl_file_documents\." \
    | state_rm_if_present
}

kubectl_delete_safe() {
  # $1: namespace (or cluster-scope if empty and kind is cluster-scoped)
  # $2+: resources (kind/name)
  local ns="$1"; shift || true
  local res
  if [[ -n "$ns" ]]; then
    for res in "$@"; do
      kubectl -n "$ns" delete "$res" --ignore-not-found=true || true
    done
  else
    for res in "$@"; do
      kubectl delete "$res" --ignore-not-found=true || true
    done
  fi
}

wait_rollout_or_fail() {
  # $1: namespace, $2: kind/name, $3: timeout
  local ns="$1"; local obj="$2"; local to="$3"
  echo "Waiting for rollout: $obj (ns=$ns)"
  kubectl -n "$ns" rollout status "$obj" --timeout="$to"
}

delete_legacy_resources() {
  echo "Deleting legacy Cilium resources (if present)..."
  kubectl_delete_safe kube-system \
    ds/cilium ds/cilium-envoy \
    deploy/cilium-operator \
    svc/cilium-envoy \
    sa/cilium sa/cilium-envoy sa/cilium-operator \
    cm/cilium-config cm/cilium-envoy-config \
    role/cilium-config-agent rolebinding/cilium-config-agent

  kubectl_delete_safe "" \
    clusterrole/cilium clusterrole/cilium-operator \
    clusterrolebinding/cilium clusterrolebinding/cilium-operator

  echo "Deleting legacy hcloud CCM resources (if present)..."
  kubectl_delete_safe kube-system \
    deploy/hcloud-cloud-controller-manager \
    sa/hcloud-cloud-controller-manager

  kubectl_delete_safe "" \
    clusterrolebinding/system:hcloud-cloud-controller-manager
}

apply_helm_releases() {
  echo "Applying Terraform (Helm releases)..."
  terraform apply -auto-approve
}

post_checks() {
  echo "Running rollout checks..."
  # Cilium
  wait_rollout_or_fail kube-system ds/cilium 10m || true
  wait_rollout_or_fail kube-system deploy/cilium-operator 10m || true
  # Hetzner CCM
  wait_rollout_or_fail kube-system deploy/hcloud-cloud-controller-manager 10m || true

  echo "Summary (kube-system):"
  kubectl -n kube-system get deploy,ds,po -l "app.kubernetes.io/instance in (cilium,hcloud-cloud-controller-manager)" || true
  # Fallback labels for older Cilium labels
  kubectl -n kube-system get po -l k8s-app=cilium || true
}

main() {
  need_bin terraform
  need_bin kubectl

  confirm

  echo "Switching to Terraform root: $ROOT_DIR"
  pushd "$ROOT_DIR" >/dev/null

  echo "Ensuring Terraform is initialized (may update .terraform/)..."
  terraform init -input=false >/dev/null

  backup_state
  remove_kubectl_items_from_state
  delete_legacy_resources
  apply_helm_releases
  post_checks

  echo "Done. Helm-managed Cilium and hcloud CCM should now be active."
  popd >/dev/null
}

main "$@"

