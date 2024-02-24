resource "oci_mysql_mysql_db_system" "monitoring_mysql_db_system" {
    #Required
    count          = var.autoscaling_monitoring && var.autoscaling_mysql_service ? 1 : 0
    admin_password = var.admin_password
    admin_username = var.admin_username
    availability_domain = var.bastion_ad
    compartment_id = var.targetCompartment
    shape_name = var.monitoring_shape_name
    subnet_id = local.subnet_id
    display_name = "autoscaling_monitoring"
    is_highly_available = false
    data_storage_size_in_gb= "50"
    backup_policy {
        is_enabled = false
    }
}

resource "oci_mysql_mysql_db_system" "billing_mysql_db_system" {
    count = var.billing ? 1 : 0

    # Required
    availability_domain = var.bastion_ad
    compartment_id = var.targetCompartment
    shape_name = var.billing_shape_name
    subnet_id = local.subnet_id

    # Optional
    admin_password = var.billing_mysql_db_admin_password
    admin_username = var.billing_mysql_db_admin_username
    backup_policy {
        is_enabled = true
        # Point-In-Time Recovery
        pitr_policy {
            is_enabled = true
        }
        retention_in_days = "7"
    }
    description = "MySQL DB System for billing"
    display_name = "billing"
    mysql_version = "8.0.35"
    port = "3306"
    port_x = "33060"

    is_highly_available = "true"
    crash_recovery = "ENABLED"
    data_storage_size_in_gb = "50"
    deletion_policy {
        automatic_backup_retention = "RETAIN"
        final_backup = "REQUIRE_FINAL_BACKUP"
        is_delete_protected = "true"
    }

    freeform_tags = {
        "Template" = "Production",
        "CreatedTime" = timestamp()
    }
}