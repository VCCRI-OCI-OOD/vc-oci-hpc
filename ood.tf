resource "oci_core_instance" "ood" {
  count               = var.ood_node ? 1 : 0
  depends_on          = [oci_core_subnet.public-subnet, null_resource.controller, oci_core_shape_management.controller-shape]
  availability_domain = var.ood_ad
  compartment_id      = var.targetCompartment
  shape               = var.ood_shape

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  dynamic "shape_config" {
    for_each = local.is_ood_flex_shape
    content {
      ocpus         = shape_config.value
      memory_in_gbs = var.ood_custom_memory ? var.ood_memory : (var.ood_shape == "VM.DenseIO.E5.Flex" || var.ood_shape == "VM.DenseIO.E6.Ax.Flex" ? 12 : 16) * shape_config.value
    }
  }
  agent_config {
    is_management_disabled = true
  }
  display_name = "${local.cluster_name}-ood"

  freeform_tags = {
    "cluster_name"        = local.cluster_name
    "config_fss_hostname" = local.config_fss_hostname
    "controller_name"     = oci_core_instance.controller.display_name
    "ood"                 = "true"
  }

  metadata = {
    ssh_authorized_keys = "${var.ssh_key}\n${tls_private_key.ssh.public_key_openssh}"
    user_data           = base64encode(file("${path.module}/cloud-init.sh"))
  }
  source_details {
    source_id               = local.controller_image
    boot_volume_size_in_gbs = var.ood_boot_volume_size
    boot_volume_vpus_per_gb = 30
    source_type             = "image"
  }

  create_vnic_details {
    subnet_id        = local.controller_subnet_id
    assign_public_ip = local.ood_bool_ip
  }
}

resource "oci_dns_rrset" "rrset-ood" {
  count           = var.ood_node ? 1 : 0
  zone_name_or_id = data.oci_dns_zones.dns_zones.zones[0].id
  domain          = "${var.ood_node ? oci_core_instance.ood[0].display_name : ""}.${local.zone_name}"
  rtype           = "A"
  items {
    domain = "${var.ood_node ? oci_core_instance.ood[0].display_name : ""}.${local.zone_name}"
    rtype  = "A"
    rdata  = var.ood_node ? oci_core_instance.ood[0].private_ip : ""
    ttl    = 3600
  }
  view_id = data.oci_dns_views.dns_views.views[0].id
}
