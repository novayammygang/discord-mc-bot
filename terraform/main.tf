# We require a project to be provided upfront
# Create a project at https://cloud.google.com/
# Make note of the project ID
# We need a storage bucket created upfront too to store the terraform state
terraform {
  backend "gcs" {
    prefix = "discord/state"
    bucket = "cyse-minecraft-tf"
  }
}

# You need to fill these locals out with the project, region and zone
# Then to boot it up, run:-
#   gcloud auth application-default login
#   terraform init
#   terraform apply
locals {
  # The Google Cloud Project ID that will host and pay for your discord server
  project = "aqueous-ray-347417"
  region  = "us-central1"
  zone    = "us-central1-a"

  enable_switch_access_group = 0
  discord_switch_access_group = ""
}


provider "google" {
  project = local.project
  region  = local.region
}

# Create service account to run service with no permissions
resource "google_service_account" "discord" {
  account_id   = "discord"
  display_name = "discord"
}

# Permenant discord disk, stays around when VM is off
resource "google_compute_disk" "discord" {
  name  = "discord"
  type  = "pd-standard"
  size = 35
  zone  = local.zone
  image = "cos-cloud/cos-stable"
}

# Permenant IP address, stays around when VM is off
resource "google_compute_address" "discord" {
  name   = "discord-ip"
  region = local.region
}

# VM to run discord, we use preemptable which will shutdown within 24 hours
resource "google_compute_instance" "discord" {
  name         = "discord"
  machine_type = "n1-standard-1"
  zone         = local.zone
  tags         = ["discord"]

  metadata_startup_script = "sudo su;docker pull gcr.io/aqueous-ray-347417/discord-mc-bot;docker run gcr.io/aqueous-ray-347417/discord-mc-bot"

  metadata = {
    enable-oslogin = "TRUE"
  }

  boot_disk {
    auto_delete = false # Keep disk after shutdown (game data)
    source      = google_compute_disk.discord.self_link
  }

  network_interface {
    network = google_compute_network.discord.name
    access_config {
      nat_ip = google_compute_address.discord.address
    }
  }

  service_account {
    email  = google_service_account.discord.email
    scopes = ["userinfo-email"]
  }

  scheduling {
    preemptible       = false # Closes within 24 hours (sometimes sooner)
    automatic_restart = false
  }
}

# Create a private network so the discord instance cannot access
# any other resources.
resource "google_compute_network" "discord" {
  name = "discord"
}

# Open the firewall for discord traffic
resource "google_compute_firewall" "discord" {
  name    = "discord"
  network = google_compute_network.discord.name
  # discord client port
  allow {
    protocol = "tcp"
    ports    = ["25565"]
  }
  # ICMP (ping)
  allow {
    protocol = "icmp"
  }
  # SSH (for RCON-CLI access)
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["discord"]
}

resource "google_project_iam_custom_role" "discordSwitcher" {
  role_id     = "DiscordSwitcher"
  title       = "Discord Switcher"
  description = "Can turn a VM on and off"
  permissions = ["compute.instances.start", "compute.instances.stop", "compute.instances.get"]
}

resource "google_project_iam_custom_role" "discordInstanceLister" {
  role_id     = "DiscordInstanceLister"
  title       = "Instance Lister"
  description = "Can list VMs in project"
  permissions = ["compute.instances.list"]
}

resource "google_compute_instance_iam_member" "switcher" {
  count = local.enable_switch_access_group
  project = local.project
  zone = local.zone
  instance_name = google_compute_instance.discord.name
  role = google_project_iam_custom_role.discordSwitcher.id
  member = "group:${local.discord_switch_access_group}"
}

resource "google_project_iam_member" "projectBrowsers" {
  count = local.enable_switch_access_group
  project = local.project
  role    = "roles/browser"
  member  = "group:${local.discord_switch_access_group}"
}

resource "google_project_iam_member" "computeViewer" {
  count = local.enable_switch_access_group
  project = local.project
  role    = google_project_iam_custom_role.discordInstanceLister.id
  member  = "group:${local.discord_switch_access_group}"
}
