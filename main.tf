terraform {
  required_version = ">= 0.12.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">=3.0.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.1"
    }
  }
}

locals {
  selector_labels = {
    "app.kubernetes.io/name"     = "redis"
    "app.kubernetes.io/instance" = var.instance
    "app.kubernetes.io/part-of"  = lookup(var.labels, "app.kubernetes.io/part-of", var.object_prefix)
  }
  common_labels = merge(var.labels, local.selector_labels, {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/component"  = "redis"
  })
}

resource "kubernetes_stateful_set_v1" "redis" {
  timeouts {
    create = var.timeout_create
    update = var.timeout_update
    delete = var.timeout_delete
  }
  metadata {
    namespace = var.namespace
    name      = var.object_prefix
    labels    = local.common_labels
  }
  wait_for_rollout = var.wait_for_rollout
  spec {
    pod_management_policy  = var.pod_management_policy
    replicas               = var.replicas
    revision_history_limit = var.revision_history
    service_name           = kubernetes_service_v1.redis.metadata[0].name
    selector {
      match_labels = local.selector_labels
    }
    update_strategy {
      type = var.update_strategy
      dynamic "rolling_update" {
        for_each = var.update_strategy == "RollingUpdate" ? [1] : []
        content {
          partition = var.update_partition
        }
      }
    }
    template {
      metadata {
        labels = local.selector_labels
      }
      spec {
        dynamic "security_context" {
          for_each = var.security_context_enabled ? [1] : []
          content {
            run_as_non_root = true
            run_as_user     = var.security_context_uid
            run_as_group    = var.security_context_gid
            fs_group        = var.security_context_gid
          }
        }
        dynamic "init_container" {
          for_each = var.security_context_enabled ? [1] : []
          content {
            image   = format("%s:%s", var.image_name, var.image_tag)
            name    = "init"
            command = ["/bin/sh", "-c", "cp /opt/bitnami/redis/etc/* /tmp_etc/"]
            volume_mount {
              name       = "etc"
              mount_path = "/tmp_etc"
            }
          }
        }
        container {
          image = format("%s:%s", var.image_name, var.image_tag)
          name  = regex("[[:alnum:]]+$", var.image_name)
          resources {
            limits = {
              cpu    = var.resources_limits_cpu
              memory = var.resources_limits_memory
            }
            requests = {
              cpu    = var.resources_requests_cpu
              memory = var.resources_requests_memory
            }
          }
          port {
            name           = "redis"
            protocol       = "TCP"
            container_port = kubernetes_service_v1.redis.spec[0].port[0].target_port
          }
          dynamic "env" {
            for_each = anytrue([var.password_required, length(var.password_secret) > 0]) ? [1] : []
            content {
              name = "REDIS_PASSWORD"
              value_from {
                secret_key_ref {
                  name = alltrue([var.password_required, length(var.password_secret) > 0]) ? var.password_secret : var.password_required ? kubernetes_secret_v1.redis[0].metadata[0].name : ""
                  key  = var.password_key
                }
              }
            }
          }
          dynamic "env" {
            for_each = alltrue([var.password_required, length(var.password_secret) > 0]) ? [] : [1]
            content {
              name  = "ALLOW_EMPTY_PASSWORD"
              value = "yes"
            }
          }
          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }
          dynamic "env" {
            for_each = [for env_var in var.env_secret : {
              name   = env_var.name
              secret = env_var.secret
              key    = env_var.key
            }]
            content {
              name = env.value["name"]
              value_from {
                secret_key_ref {
                  name = env.value["secret"]
                  key  = env.value["key"]
                }
              }
            }
          }
          volume_mount {
            name       = "data"
            mount_path = "/bitnami/redis/data"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/opt/bitnami/redis/tmp"
          }
          dynamic "volume_mount" {
            for_each = var.security_context_enabled ? [1] : []
            content {
              name       = "etc"
              mount_path = "/opt/bitnami/redis/etc"
            }
          }
          volume_mount {
            name       = "logs"
            mount_path = "/opt/bitnami/redis/logs"
          }
          dynamic "readiness_probe" {
            for_each = var.readiness_probe_enabled ? [1] : []
            content {
              initial_delay_seconds = var.readiness_probe_initial_delay
              period_seconds        = var.readiness_probe_period
              timeout_seconds       = var.readiness_probe_timeout
              success_threshold     = var.readiness_probe_success
              failure_threshold     = var.readiness_probe_failure
              exec {
                command = ["/bin/sh", "-c", "if [ -z $${REDIS_PASSWORD} ]; then redis-cli PING | grep -q PONG; else redis-cli -a $${REDIS_PASSWORD} PING 2>/dev/null | grep -q PONG; fi"]
              }
            }
          }
          dynamic "liveness_probe" {
            for_each = var.liveness_probe_enabled ? [1] : []
            content {
              initial_delay_seconds = var.liveness_probe_initial_delay
              period_seconds        = var.liveness_probe_period
              timeout_seconds       = var.liveness_probe_timeout
              success_threshold     = var.liveness_probe_success
              failure_threshold     = var.liveness_probe_failure
              exec {
                command = ["/bin/sh", "-c", "if [ -z $${REDIS_PASSWORD} ]; then redis-cli PING | grep -q PONG; else redis-cli -a $${REDIS_PASSWORD} PING 2>/dev/null | grep -q PONG; fi"]
              }
            }
          }
          dynamic "startup_probe" {
            for_each = var.startup_probe_enabled ? [1] : []
            content {
              initial_delay_seconds = var.startup_probe_initial_delay
              period_seconds        = var.startup_probe_period
              timeout_seconds       = var.startup_probe_timeout
              success_threshold     = var.startup_probe_success
              failure_threshold     = var.startup_probe_failure
              exec {
                command = ["/bin/sh", "-c", "if [ -z $${REDIS_PASSWORD} ]; then redis-cli PING | grep -q PONG; else redis-cli -a $${REDIS_PASSWORD} PING 2>/dev/null | grep -q PONG; fi"]
              }
            }
          }
        }
        volume {
          name = "data"
          dynamic "empty_dir" {
            for_each = length(var.pvc_name) > 0 ? [] : [1]
            content {
              medium     = var.volume_data_medium
              size_limit = var.volume_data_size
            }
          }
          dynamic "persistent_volume_claim" {
            for_each = length(var.pvc_name) > 0 ? [1] : []
            content {
              claim_name = var.pvc_name
              read_only  = false
            }
          }
        }
        volume {
          name = "tmp"
          empty_dir {
            medium     = var.volume_tmp_medium
            size_limit = var.volume_tmp_size
          }
        }
        dynamic "volume" {
          for_each = var.security_context_enabled ? [1] : []
          content {
            name = "etc"
            empty_dir {
              medium     = var.volume_tmp_medium
              size_limit = var.volume_tmp_size
            }
          }
        }
        volume {
          name = "logs"
          empty_dir {
            medium     = var.volume_logs_medium
            size_limit = var.volume_logs_size
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    namespace   = var.namespace
    name        = var.object_prefix
    labels      = local.common_labels
    annotations = var.service_annotations
  }
  spec {
    selector                = local.selector_labels
    session_affinity        = var.service_session_affinity
    type                    = var.service_type
    external_traffic_policy = contains(["LoadBalancer", "NodePort"], var.service_type) ? var.service_traffic_policy : null
    port {
      name        = "redis"
      protocol    = "TCP"
      target_port = 6379
      port        = var.service_port
    }
  }
}

resource "kubernetes_secret_v1" "redis" {
  count = length(var.password_secret) == 0 ? var.password_required ? 1 : 0 : 0
  metadata {
    namespace = var.namespace
    name      = var.object_prefix
    labels    = local.common_labels
  }
  data = {
    (var.password_key) = random_password.password.0.result
  }
}


resource "random_password" "password" {
  count   = length(var.password_secret) == 0 ? var.password_required ? 1 : 0 : 0
  length  = 16
  special = false
}
