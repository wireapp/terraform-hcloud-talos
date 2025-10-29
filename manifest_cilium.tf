locals {
  cilium_default_set = var.cilium_values == null ? [
    {
      name  = "operator.replicas"
      value = tostring(var.control_plane_count > 1 ? 2 : 1)
    },
    {
      name  = "ipam.mode"
      value = "kubernetes"
    },
    {
      name  = "routingMode"
      value = "native"
    },
    {
      name  = "ipv4NativeRoutingCIDR"
      value = local.pod_ipv4_cidr
    },
    {
      name  = "kubeProxyReplacement"
      value = "true"
    },
    {
      name  = "bpf.masquerade"
      value = "false"
    },
    {
      name  = "loadBalancer.acceleration"
      value = "native"
    },
    {
      name  = "encryption.enabled"
      value = var.cilium_enable_encryption ? "true" : "false"
    },
    {
      name  = "encryption.type"
      value = "wireguard"
    },
    {
      name  = "securityContext.capabilities.ciliumAgent"
      value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
    },
    {
      name  = "securityContext.capabilities.cleanCiliumState"
      value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
    },
    {
      name  = "cgroup.autoMount.enabled"
      value = "false"
    },
    {
      name  = "cgroup.hostRoot"
      value = "/sys/fs/cgroup"
    },
    {
      name  = "k8sServiceHost"
      value = "127.0.0.1"
    },
    {
      name  = "k8sServicePort"
      value = tostring(local.api_port_kube_prism)
    },
    {
      name  = "hubble.enabled"
      value = "false"
    },
    {
      name  = "prometheus.serviceMonitor.enabled"
      value = var.cilium_enable_service_monitors ? "true" : "false"
    },
    {
      name  = "prometheus.serviceMonitor.trustCRDsExist"
      value = var.cilium_enable_service_monitors ? "true" : "false"
    },
    {
      name  = "operator.prometheus.serviceMonitor.enabled"
      value = var.cilium_enable_service_monitors ? "true" : "false"
    }
  ] : []
}

resource "helm_release" "cilium" {
  count      = var.control_plane_count > 0 ? 1 : 0
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_version

  wait             = true
  timeout          = 1200
  cleanup_on_fail  = true
  create_namespace = false

  # If user-provided values are supplied, pass them through.
  values = var.cilium_values == null ? [] : var.cilium_values

  dynamic "set" {
    for_each = local.cilium_default_set
    content {
      name  = set.value.name
      value = set.value.value
    }
  }

  depends_on = [data.http.talos_health]
}

resource "helm_release" "prometheus_operator_crds" {
  count      = var.deploy_prometheus_operator_crds && var.control_plane_count > 0 ? 1 : 0
  name       = "prometheus-operator-crds"
  namespace  = "kube-system"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-operator-crds"

  wait            = true
  timeout         = 600
  cleanup_on_fail = true

  depends_on = [data.http.talos_health]
}
