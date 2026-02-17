resource "hcloud_placement_group" "control_plane" {
  name = "${local.cluster_prefix}control-plane"
  type = "spread"
  labels = {
    "cluster" = var.cluster_name
  }
}

resource "hcloud_placement_group" "worker" {
  count  = local.total_worker_count > 0 ? ceil(local.total_worker_count / var.worker_placement_group_size) : 0
  # Preserve original name for the first group to avoid drift
  name   = "${local.cluster_prefix}worker${count.index == 0 ? "" : "-${count.index + 1}"}"
  type   = "spread"
  labels = {
    "cluster" = var.cluster_name
  }
}

moved {
  from = hcloud_placement_group.worker
  to   = hcloud_placement_group.worker[0]
}
