output "engine_public_ip" {
  description = "Public IP of the engine/gateway VM."
  value       = google_compute_instance.engine.network_interface[0].access_config[0].nat_ip
}

output "api_url" {
  description = "The JSON inference API endpoint."
  value       = "http://${google_compute_instance.engine.network_interface[0].access_config[0].nat_ip}:3111/v1/chat/completions"
}

output "engine_internal_ip" {
  description = "Private IP the workers use to reach the engine."
  value       = var.engine_internal_ip
}

output "ssh_engine" {
  description = "Command to SSH into the engine VM."
  value       = "gcloud compute ssh alchemyst-engine --zone ${var.zone} --tunnel-through-iap"
}

output "ssh_caller" {
  description = "Command to SSH into the caller-worker VM."
  value       = "gcloud compute ssh alchemyst-caller-worker --zone ${var.zone} --tunnel-through-iap"
}

output "ssh_inference" {
  description = "Command to SSH into the inference-worker VM."
  value       = "gcloud compute ssh alchemyst-inference-worker --zone ${var.zone} --tunnel-through-iap"
}
