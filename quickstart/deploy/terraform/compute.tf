# Reserve a fixed internal IP for the engine so the worker VMs know where
# to connect (III_URL) without waiting for the engine to be created first.
resource "google_compute_address" "engine_internal" {
  name         = "alchemyst-engine-ip"
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.subnet.id
  address      = var.engine_internal_ip
  region       = var.region
}

data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# --- Engine VM: the public-facing gateway. Hosts the JSON API. ---
resource "google_compute_instance" "engine" {
  name         = "alchemyst-engine"
  machine_type = var.machine_type_engine
  zone         = var.zone
  tags         = ["engine", "iii"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    network_ip = google_compute_address.engine_internal.address
    access_config {} # ephemeral public IP
  }

  metadata_startup_script = templatefile("${path.module}/startup-engine.sh", {
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
  })
}

# --- Caller-worker VM: private, no public IP. ---
resource "google_compute_instance" "caller" {
  name         = "alchemyst-caller-worker"
  machine_type = var.machine_type_caller
  zone         = var.zone
  tags         = ["worker", "iii"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    # no access_config block => no public IP
  }

  metadata_startup_script = templatefile("${path.module}/startup-caller.sh", {
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
    engine_ip   = var.engine_internal_ip
  })
}

# --- Inference-worker VM: private, no public IP. Larger (model needs RAM). ---
resource "google_compute_instance" "inference" {
  name         = "alchemyst-inference-worker"
  machine_type = var.machine_type_inference
  zone         = var.zone
  tags         = ["worker", "iii"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = 30
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    # no access_config block => no public IP
  }

  metadata_startup_script = templatefile("${path.module}/startup-inference.sh", {
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
    engine_ip   = var.engine_internal_ip
  })
}
