terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}

provider "oci" {
  region = var.region
}

resource "random_password" "wp_admin" {
  length  = 24
  special = false
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_vcn" "radar" {
  compartment_id = var.compartment_ocid
  cidr_blocks     = ["10.42.0.0/16"]
  display_name    = "radar-commerce-vcn"
  dns_label       = "radarvcn"
}

resource "oci_core_internet_gateway" "radar" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.radar.id
  display_name   = "radar-commerce-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.radar.id
  display_name   = "radar-commerce-public-routes"

  route_rules {
    network_entity_id = oci_core_internet_gateway.radar.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_network_security_group" "web" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.radar.id
  display_name   = "radar-commerce-web-nsg"
}

resource "oci_core_network_security_group_security_rule" "egress_all" {
  network_security_group_id = oci_core_network_security_group.web.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

resource "oci_core_network_security_group_security_rule" "http" {
  network_security_group_id = oci_core_network_security_group.web.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "https" {
  network_security_group_id = oci_core_network_security_group.web.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "ssh" {
  network_security_group_id = oci_core_network_security_group.web.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.radar.id
  cidr_block                 = "10.42.10.0/24"
  display_name               = "radar-commerce-public-subnet"
  dns_label                  = "radarpub"
  route_table_id             = oci_core_route_table.public.id
  prohibit_public_ip_on_vnic = false
}

locals {
  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    wp_admin_password = random_password.wp_admin.result
  })
}

resource "oci_core_instance" "radar" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain_name
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"
  preserve_boot_volume = false

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = "radarcommerce"
    nsg_ids          = [oci_core_network_security_group.web.id]
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = 50
  }

  metadata = merge(
    {
      user_data = base64encode(local.cloud_init)
    },
    trimspace(var.ssh_public_key) != "" ? {
      ssh_authorized_keys = trimspace(var.ssh_public_key)
    } : {}
  )

  freeform_tags = {
    Project = "Radar Commerce"
    Cost    = "Always Free target"
  }
}
