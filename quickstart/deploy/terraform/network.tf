# Custom-mode VPC: no auto subnets, we define exactly one private subnet.
resource "google_compute_network" "vpc" {
  name                    = "alchemyst-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "alchemyst-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Cloud Router + Cloud NAT: lets the private VMs reach the internet
# (clone the repo, pull base images, download the model) WITHOUT being
# reachable from the internet themselves.
resource "google_compute_router" "router" {
  name    = "alchemyst-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "alchemyst-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
