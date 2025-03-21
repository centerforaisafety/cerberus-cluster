resource "oci_file_storage_file_system" "FSS" {
  count               = var.create_fss ? 1 : 0
  availability_domain = var.fss_ad
  compartment_id      = var.fss_compartment
  display_name        = "${local.cluster_name}-fss"
}

resource "oci_file_storage_mount_target" "FSSMountTarget" {
  count               = var.create_fss ? var.mount_target_count : 0
  availability_domain = var.fss_ad
  compartment_id      = var.fss_compartment
  subnet_id           = local.subnet_id
  display_name        = "${local.cluster_name}-mt-${count.index}"
  hostname_label      = "fileserver${count.index}"
}

resource "oci_file_storage_export" "FSSExport" {
  count          = var.create_fss ? var.mount_target_count : 0
  export_set_id  = oci_file_storage_mount_target.FSSMountTarget[count.index].export_set_id
  file_system_id = oci_file_storage_file_system.FSS[0].id
  path           = var.nfs_source_path
  export_options {
    source          = data.oci_core_vcn.vcn.cidr_block
    access          = "READ_WRITE"
    identity_squash = "NONE"
  }
}

resource "oci_file_storage_file_system" "FSS_home" {
  count                       = var.create_home_fss ? 1 : 0
  availability_domain         = var.ad
  compartment_id              = var.targetCompartment
  display_name                = "${local.cluster_name}-fss-home"
  }

resource "oci_file_storage_mount_target" "FSSMountTarget_home" {
  count               = var.create_home_fss ? 1 : 0
  availability_domain = var.ad
  compartment_id      = var.targetCompartment
  subnet_id           = local.subnet_id
  display_name        = "${local.cluster_name}-mt-home"  
  hostname_label      = "fileserver"
}

resource "oci_file_storage_export" "FSSExport_home" {
  count          = var.create_home_fss ? 1 : 0
  export_set_id  = oci_file_storage_mount_target.FSSMountTarget_home.0.export_set_id
  file_system_id = oci_file_storage_file_system.FSS_home.0.id
  path           = var.home_fss_source_path
  export_options {
    source          = data.oci_core_vcn.vcn.cidr_block
    access          = "READ_WRITE"
    identity_squash = "NONE"
  }
}