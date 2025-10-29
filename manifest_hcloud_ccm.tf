resource "helm_release" "hcloud_ccm" {
  count      = var.control_plane_count > 0 ? 1 : 0
  name       = "hcloud-cloud-controller-manager"
  namespace  = "kube-system"
  repository = "https://charts.hetzner.cloud"
  chart      = "hcloud-cloud-controller-manager"
  version    = var.hcloud_ccm_version

  wait             = true
  timeout          = 600
  cleanup_on_fail  = true
  create_namespace = false

  set {
    name  = "networking.enabled"
    value = "true"
  }

  set {
    name  = "networking.clusterCIDR"
    value = local.pod_ipv4_cidr
  }

  depends_on = [data.http.talos_health]
}
