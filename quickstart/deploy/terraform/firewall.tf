# Public: anyone may hit the JSON API (port 3111) on the engine VM only.
resource "google_compute_firewall" "allow_api" {
  name      = "alchemyst-allow-api"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["3111"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["engine"]
}

# Internal: VMs inside the subnet may talk to each other. This is what
# carries the worker RPC traffic (port 49134) across the subnet.
resource "google_compute_firewall" "allow_internal" {
  name      = "alchemyst-allow-internal"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["iii"]
}

# SSH only via Google IAP. The worker VMs have no public IP, so this is
# the only way in. 35.235.240.0/20 is Google's fixed IAP source range.
resource "google_compute_firewall" "allow_iap_ssh" {
  name      = "alchemyst-allow-iap-ssh"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["iii"]
}
