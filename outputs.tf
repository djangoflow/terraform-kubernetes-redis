output "hostname" {
  description = "Name of the kubernetes service"
  value       = kubernetes_service_v1.redis.metadata[0].name
}

output "port" {
  description = "Port for the kubernetes service"
  value       = var.service_port
}

output "password_secret" {
  description = "Secret that is created with the Redis password"
  value       = alltrue([var.password_required, length(var.password_secret) > 0]) ? var.password_secret : var.password_required ? kubernetes_secret_v1.redis[0].metadata[0].name : ""
}

output "password_key" {
  description = "Key for the Redis password in the secret"
  value       = var.password_key
}


output "redis_url" {
  depends_on = [random_password.password.0]
  value      = "redis://:${random_password.password.0.result}@${kubernetes_service_v1.redis.metadata[0].name}.${var.namespace}.svc.cluster.local:${var.service_port}/"
}
