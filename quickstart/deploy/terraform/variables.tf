variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used to name and tag all resources."
  type        = string
  default     = "alchemyst"
}

variable "repo_url" {
  description = "Public Git repo URL the VMs clone on boot to build their containers."
  type        = string
}

variable "repo_branch" {
  description = "Git branch to deploy."
  type        = string
  default     = "master"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (engine + NAT Gateway)."
  type        = string
  default     = "10.10.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet (workers)."
  type        = string
  default     = "10.10.2.0/24"
}

variable "engine_private_ip" {
  description = "Static private IP for the engine VM. Must be inside public_subnet_cidr."
  type        = string
  default     = "10.10.1.10"
}

variable "instance_type_engine" {
  description = "EC2 instance type for the engine/gateway VM."
  type        = string
  default     = "t3.small"
}

variable "instance_type_caller" {
  description = "EC2 instance type for the caller-worker VM."
  type        = string
  default     = "t3.small"
}

variable "instance_type_inference" {
  description = "EC2 instance type for the inference-worker VM (needs RAM for the model)."
  type        = string
  default     = "m7i-flex.large"
}
