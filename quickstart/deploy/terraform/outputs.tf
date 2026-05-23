output "engine_public_ip" {
  description = "Public IP of the engine/gateway VM."
  value       = aws_instance.engine.public_ip
}

output "api_url" {
  description = "The JSON inference API endpoint."
  value       = "http://${aws_instance.engine.public_ip}:3111/v1/chat/completions"
}

output "engine_private_ip" {
  description = "Private IP the workers use to reach the engine."
  value       = aws_instance.engine.private_ip
}

output "ssm_engine" {
  description = "Open an SSM session on the engine VM."
  value       = "aws ssm start-session --target ${aws_instance.engine.id} --region ${var.region}"
}

output "ssm_caller" {
  description = "Open an SSM session on the caller-worker VM."
  value       = "aws ssm start-session --target ${aws_instance.caller.id} --region ${var.region}"
}

output "ssm_inference" {
  description = "Open an SSM session on the inference-worker VM."
  value       = "aws ssm start-session --target ${aws_instance.inference.id} --region ${var.region}"
}
