variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the VMs."
  type        = string
  default     = "us-central1-a"
}

variable "repo_url" {
  description = "Public Git repo URL the VMs clone on boot to build their containers."
  type        = string
}

variable "repo_branch" {
  description = "Git branch to deploy."
  type        = string
  default     = "main"
}

variable "subnet_cidr" {
  description = "CIDR range for the private subnet."
  type        = string
  default     = "10.10.0.0/24"
}

variable "engine_internal_ip" {
  description = "Static internal IP for the engine VM. Must be inside subnet_cidr."
  type        = string
  default     = "10.10.0.10"
}

variable "machine_type_engine" {
  description = "Machine type for the engine/gateway VM."
  type        = string
  default     = "e2-small"
}

variable "machine_type_caller" {
  description = "Machine type for the caller-worker VM."
  type        = string
  default     = "e2-small"
}

variable "machine_type_inference" {
  description = "Machine type for the inference-worker VM (needs RAM for the model)."
  type        = string
  default     = "e2-standard-2"
}
