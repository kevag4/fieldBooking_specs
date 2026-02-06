---
inclusion: manual
---

# Terraform DigitalOcean Infrastructure Context

> When designing or implementing Terraform infrastructure code for the field-booking-platform on DigitalOcean, follow the patterns and standards in this document. It codifies best practices from antonbabenko's Terraform Best Practices, Gruntwork's infrastructure-modules pattern, terraform-aws-modules' module design, and DigitalOcean's official Terraform provider documentation.

## 1. Key Concepts & Hierarchy

### Resource Hierarchy (antonbabenko)

```
composition (environment)
  └── infrastructure-module (e.g., networking, database, kubernetes)
        └── resource-module (e.g., doks-cluster, managed-postgres)
              └── individual resources (digitalocean_kubernetes_cluster, etc.)
```

| Concept | Description |
|---------|-------------|
| Resource | Single Terraform resource (e.g., `digitalocean_kubernetes_cluster`) |
| Resource Module | Collection of connected resources performing one function (e.g., DOKS + node pools) |
| Infrastructure Module | Collection of resource modules serving one purpose (e.g., full environment) |
| Composition | Collection of infrastructure modules spanning environments |

### Data Flow Between Layers

- Access between resource modules: via module outputs
- Access between infrastructure modules: via `terraform_remote_state` data sources
- Access between compositions: via remote state or shared data stores

## 2. Repository Structure (Gruntwork Pattern)

### Monorepo Layout for `field-booking-infrastructure`

```
field-booking-infrastructure/
├── modules/                              # Reusable resource modules
│   ├── doks-cluster/                     # DOKS Kubernetes cluster
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── README.md
│   ├── managed-postgres/                 # Managed PostgreSQL + PostGIS
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   ├── managed-redis/                    # Managed Redis
│   ├── spaces/                           # S3-compatible object storage
│   ├── container-registry/               # Private Docker registry
│   ├── vpc/                              # VPC networking
│   ├── load-balancer/                    # Load balancer + SSL
│   ├── dns/                              # Domain and DNS records
│   ├── firewall/                         # Firewall rules
│   └── project/                          # DO Project grouping
│
├── environments/                         # Compositions (one per environment)
│   ├── shared/                           # Shared cluster (dev/test/staging)
│   │   ├── main.tf                       # Calls modules
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   ├── terraform.tfvars              # Environment-specific values
│   │   └── backend.tf                    # Remote state config
│   └── production/                       # Dedicated production cluster
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── terraform.tfvars
│       └── backend.tf
│
├── kubernetes/                           # K8s manifests deployed after infra
│   ├── base/                             # Shared base manifests (Kustomize)
│   │   ├── namespaces/
│   │   ├── nginx-ingress/
│   │   ├── cert-manager/
│   │   └── observability/
│   ├── overlays/                         # Environment-specific overrides
│   │   ├── dev/
│   │   ├── test/
│   │   ├── staging/
│   │   └── production/
│   └── helm-values/                      # Helm chart value files
│       ├── prometheus-values.yaml
│       ├── grafana-values.yaml
│       ├── jaeger-values.yaml
│       ├── loki-values.yaml
│       └── istio-values.yaml
│
├── scripts/                              # Operational scripts
│   ├── backup-verify.sh
│   ├── secret-rotation.sh
│   └── cluster-maintenance.sh
│
├── .github/
│   └── workflows/
│       ├── terraform-shared.yml          # CI/CD for shared environment
│       └── terraform-production.yml      # CI/CD for production
│
├── .terraform-version                    # tfenv version pinning
├── .tflint.hcl                           # Linting configuration
└── README.md
```

### Why Monorepo (for this project)

Per Gruntwork's analysis, monorepo is preferred when:
- Single team manages all infrastructure
- Global changes (provider upgrades, security fixes) need to happen atomically
- Continuous integration across modules is important
- Fewer repos to manage permissions and pipelines

The trade-off (all modules get same version tag) is acceptable for a single-product platform.

## 3. File Structure Per Module (terraform-aws-modules Pattern)

Every module MUST contain these files in this exact structure:

```
modules/<module-name>/
├── main.tf           # Resource definitions, calls to sub-resources
├── variables.tf      # Input variable declarations
├── outputs.tf        # Output value declarations
├── versions.tf       # Required providers and Terraform version constraints
├── README.md         # Module documentation with usage examples
└── examples/         # (Optional) Example usage configurations
    └── basic/
        └── main.tf
```

### File Responsibilities

| File | Contains | Never Contains |
|------|----------|----------------|
| `main.tf` | Resource blocks, data sources, locals | Variable declarations, output declarations |
| `variables.tf` | All `variable` blocks | Resource blocks, outputs |
| `outputs.tf` | All `output` blocks | Resource blocks, variables |
| `versions.tf` | `terraform { required_providers {} }` block, version constraints | Resources, variables, outputs |
| `terraform.tfvars` | Only in compositions (environments), never in modules | — |

### Composition (Environment) Files

```
environments/<env>/
├── main.tf           # Module calls with environment-specific parameters
├── variables.tf      # Environment-level variables
├── outputs.tf        # Environment-level outputs
├── versions.tf       # Provider and Terraform version constraints
├── backend.tf        # Remote state backend configuration (Spaces)
└── terraform.tfvars  # Actual values for this environment
```

## 4. Naming Conventions (antonbabenko)

### Terraform Names (HCL identifiers)

| Rule | Example ✅ | Anti-pattern ❌ |
|------|-----------|----------------|
| Use `_` (underscore) everywhere | `resource "digitalocean_kubernetes_cluster" "shared" {}` | `"shared-cluster"` |
| Lowercase letters and numbers only | `variable "node_count"` | `variable "NodeCount"` |
| Don't repeat resource type in name | `resource "digitalocean_database_cluster" "primary" {}` | `"primary_database_cluster"` |
| Use `this` when only one of its type | `resource "digitalocean_vpc" "this" {}` | `"main_vpc"` |
| Singular nouns for names | `variable "cluster_name"` | `variable "cluster_names"` (unless list) |
| Plural for list/map variables | `variable "node_pool_tags"` (type = list) | `variable "node_pool_tag"` |

### Resource Argument Ordering

```hcl
resource "digitalocean_kubernetes_cluster" "shared" {
  # 1. count/for_each (first, separated by newline)
  count = var.create_cluster ? 1 : 0

  # 2. Required arguments
  name    = var.cluster_name
  region  = var.region
  version = var.kubernetes_version

  # 3. Optional arguments
  vpc_uuid     = var.vpc_id
  auto_upgrade = var.auto_upgrade
  ha           = var.enable_ha

  # 4. Nested blocks
  node_pool {
    name       = "${var.cluster_name}-default"
    size       = var.default_node_size
    auto_scale = var.enable_autoscaling
    min_nodes  = var.min_nodes
    max_nodes  = var.max_nodes
  }

  # 5. Tags (last real argument)
  tags = var.tags

  # 6. Lifecycle (after empty line)

  lifecycle {
    ignore_changes = [version]
  }
}
```

### Cloud Resource Names (human-visible)

| Rule | Example |
|------|---------|
| Use `-` (dash) in cloud resource names | `name = "fb-shared-cluster"` |
| Include project prefix | `fb-` (field-booking) |
| Include environment | `fb-prod-postgres` |
| Include purpose | `fb-shared-worker-pool` |

### Variable Naming

```hcl
# Order: description, type, default, validation
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "node_sizes" {
  description = "List of droplet sizes for worker nodes"
  type        = list(string)
  default     = ["s-4vcpu-8gb"]
}

variable "enable_autoscaling" {
  description = "Whether to enable node pool autoscaling"
  type        = bool
  default     = false
}

# Use positive names — avoid double negatives
# ✅ enable_ha, enable_autoscaling, create_read_replica
# ❌ disable_ha, no_autoscaling, skip_read_replica
```

### Output Naming

Follow `{name}_{type}_{attribute}` pattern:

```hcl
output "shared_cluster_id" {
  description = "The ID of the shared DOKS cluster"
  value       = digitalocean_kubernetes_cluster.shared.id
}

output "shared_cluster_endpoint" {
  description = "The API endpoint of the shared DOKS cluster"
  value       = digitalocean_kubernetes_cluster.shared.endpoint
}

output "primary_database_host" {
  description = "The hostname of the primary PostgreSQL cluster"
  value       = digitalocean_database_cluster.primary.host
}

output "primary_database_port" {
  description = "The port of the primary PostgreSQL cluster"
  value       = digitalocean_database_cluster.primary.port
}
```

## 5. Module Design Patterns (terraform-aws-modules)

### Conditional Resource Creation

Every module MUST support a `create` variable to enable/disable the entire module:

```hcl
variable "create" {
  description = "Whether to create the resources in this module"
  type        = bool
  default     = true
}

resource "digitalocean_kubernetes_cluster" "this" {
  count = var.create ? 1 : 0
  # ...
}

output "cluster_id" {
  description = "The ID of the Kubernetes cluster"
  value       = try(digitalocean_kubernetes_cluster.this[0].id, null)
}
```

### Use `try()` for Safe Output Access

```hcl
# ✅ Safe — handles count = 0
output "cluster_endpoint" {
  value = try(digitalocean_kubernetes_cluster.this[0].endpoint, "")
}

# ❌ Unsafe — fails when count = 0
output "cluster_endpoint" {
  value = digitalocean_kubernetes_cluster.this[0].endpoint
}
```

### Sensible Defaults with Override Capability

```hcl
variable "node_size" {
  description = "Droplet size for worker nodes"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "node_count" {
  description = "Number of worker nodes (ignored if autoscaling enabled)"
  type        = number
  default     = 3
}

variable "auto_scale" {
  description = "Enable autoscaling for the node pool"
  type        = bool
  default     = false
}

variable "min_nodes" {
  description = "Minimum nodes when autoscaling is enabled"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum nodes when autoscaling is enabled"
  type        = number
  default     = 5
}
```

### Tags as a First-Class Concern

```hcl
variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = list(string)
  default     = []
}

locals {
  default_tags = [
    "managed-by:terraform",
    "project:field-booking",
    "environment:${var.environment}"
  ]
  all_tags = distinct(concat(local.default_tags, var.tags))
}
```

### Description on Every Variable and Output

```hcl
# ✅ Always include description — even if it seems obvious
variable "region" {
  description = "DigitalOcean region where resources will be created"
  type        = string
  default     = "fra1"
}

# ❌ Never skip description
variable "region" {
  type    = string
  default = "fra1"
}
```

## 6. State Management

### Remote State with DigitalOcean Spaces

Use Spaces (S3-compatible) as the Terraform backend:

```hcl
# backend.tf (in each environment)
terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://fra1.digitaloceanspaces.com"
    }
    bucket                      = "fb-terraform-state"
    key                         = "shared/terraform.tfstate"  # or "production/terraform.tfstate"
    region                      = "us-east-1"                 # Required but ignored by DO
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
```

### State Isolation Rules

| Environment | State File Key | Rationale |
|-------------|---------------|-----------|
| Shared (dev/test/staging) | `shared/terraform.tfstate` | Single cluster, namespace isolation |
| Production | `production/terraform.tfstate` | Dedicated cluster, full isolation |

### Cross-Environment Data Access

```hcl
# In production, reference shared state if needed
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    endpoints = {
      s3 = "https://fra1.digitaloceanspaces.com"
    }
    bucket                      = "fb-terraform-state"
    key                         = "shared/terraform.tfstate"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
```

## 7. DigitalOcean Provider Patterns

### Provider Configuration

```hcl
# versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.75"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}
```

### DOKS Cluster Module Pattern

```hcl
# modules/doks-cluster/main.tf
resource "digitalocean_kubernetes_cluster" "this" {
  count = var.create ? 1 : 0

  name         = var.cluster_name
  region       = var.region
  version      = var.kubernetes_version
  vpc_uuid     = var.vpc_id
  auto_upgrade = var.auto_upgrade
  surge_upgrade = var.surge_upgrade
  ha           = var.enable_ha

  registry_integration = var.registry_integration

  node_pool {
    name       = "${var.cluster_name}-default"
    size       = var.default_node_size
    auto_scale = var.enable_autoscaling
    min_nodes  = var.enable_autoscaling ? var.min_nodes : null
    max_nodes  = var.enable_autoscaling ? var.max_nodes : null
    node_count = var.enable_autoscaling ? null : var.node_count
    tags       = local.all_tags
    labels     = var.node_labels
  }

  dynamic "maintenance_policy" {
    for_each = var.maintenance_day != null ? [1] : []
    content {
      day        = var.maintenance_day
      start_time = var.maintenance_start_time
    }
  }

  tags = local.all_tags

  lifecycle {
    ignore_changes = [version]
  }

  timeouts {
    create = "30m"
  }
}
```

### Additional Node Pools (Separate Resource)

```hcl
resource "digitalocean_kubernetes_node_pool" "additional" {
  for_each = var.additional_node_pools

  cluster_id = digitalocean_kubernetes_cluster.this[0].id
  name       = each.value.name
  size       = each.value.size
  auto_scale = lookup(each.value, "auto_scale", false)
  min_nodes  = lookup(each.value, "min_nodes", 1)
  max_nodes  = lookup(each.value, "max_nodes", 3)
  node_count = lookup(each.value, "node_count", 1)
  tags       = concat(local.all_tags, lookup(each.value, "tags", []))
  labels     = lookup(each.value, "labels", {})

  dynamic "taint" {
    for_each = lookup(each.value, "taints", [])
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }
}
```

### Managed PostgreSQL Module Pattern

```hcl
# modules/managed-postgres/main.tf
resource "digitalocean_database_cluster" "this" {
  count = var.create ? 1 : 0

  name                 = var.cluster_name
  engine               = "pg"
  version              = var.postgres_version
  size                 = var.size
  region               = var.region
  node_count           = var.node_count
  private_network_uuid = var.vpc_id
  project_id           = var.project_id

  tags = local.all_tags

  maintenance_window {
    day  = var.maintenance_day
    hour = var.maintenance_hour
  }
}

# Read replica for analytics
resource "digitalocean_database_replica" "read_replica" {
  count = var.create && var.create_read_replica ? 1 : 0

  cluster_id           = digitalocean_database_cluster.this[0].id
  name                 = "${var.cluster_name}-replica"
  size                 = var.replica_size != null ? var.replica_size : var.size
  region               = var.region
  private_network_uuid = var.vpc_id

  tags = local.all_tags
}

# Separate schemas per service
resource "digitalocean_database_db" "platform" {
  count      = var.create ? 1 : 0
  cluster_id = digitalocean_database_cluster.this[0].id
  name       = "platform"
}

resource "digitalocean_database_db" "transaction" {
  count      = var.create ? 1 : 0
  cluster_id = digitalocean_database_cluster.this[0].id
  name       = "transaction"
}

# Database users per service
resource "digitalocean_database_user" "platform_service" {
  count      = var.create ? 1 : 0
  cluster_id = digitalocean_database_cluster.this[0].id
  name       = "platform_service"
}

resource "digitalocean_database_user" "transaction_service" {
  count      = var.create ? 1 : 0
  cluster_id = digitalocean_database_cluster.this[0].id
  name       = "transaction_service"
}

# Firewall — restrict to VPC and DOKS cluster
resource "digitalocean_database_firewall" "this" {
  count      = var.create ? 1 : 0
  cluster_id = digitalocean_database_cluster.this[0].id

  dynamic "rule" {
    for_each = var.firewall_rules
    content {
      type  = rule.value.type
      value = rule.value.value
    }
  }
}
```

### Managed Redis Module Pattern

```hcl
# modules/managed-redis/main.tf
resource "digitalocean_database_cluster" "this" {
  count = var.create ? 1 : 0

  name                 = var.cluster_name
  engine               = "redis"
  version              = var.redis_version
  size                 = var.size
  region               = var.region
  node_count           = var.node_count
  private_network_uuid = var.vpc_id
  project_id           = var.project_id
  eviction_policy      = var.eviction_policy

  tags = local.all_tags

  maintenance_window {
    day  = var.maintenance_day
    hour = var.maintenance_hour
  }
}

resource "digitalocean_database_firewall" "this" {
  count      = var.create ? 1 : 0
  cluster_id = digitalocean_database_cluster.this[0].id

  dynamic "rule" {
    for_each = var.firewall_rules
    content {
      type  = rule.value.type
      value = rule.value.value
    }
  }
}
```

### VPC Module Pattern

```hcl
# modules/vpc/main.tf
resource "digitalocean_vpc" "this" {
  count = var.create ? 1 : 0

  name        = var.vpc_name
  region      = var.region
  description = var.description
  ip_range    = var.ip_range
}
```

### Spaces (Object Storage) Module Pattern

```hcl
# modules/spaces/main.tf
resource "digitalocean_spaces_bucket" "this" {
  count = var.create ? 1 : 0

  name   = var.bucket_name
  region = var.region
  acl    = var.acl

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      enabled = lifecycle_rule.value.enabled
      prefix  = lifecycle_rule.value.prefix
      expiration {
        days = lifecycle_rule.value.expiration_days
      }
    }
  }
}

# CDN for public assets
resource "digitalocean_cdn" "this" {
  count = var.create && var.enable_cdn ? 1 : 0

  origin           = digitalocean_spaces_bucket.this[0].bucket_domain_name
  custom_domain    = var.cdn_custom_domain
  certificate_name = var.cdn_certificate_name
  ttl              = var.cdn_ttl
}
```

### Container Registry Module Pattern

```hcl
# modules/container-registry/main.tf
resource "digitalocean_container_registry" "this" {
  count = var.create ? 1 : 0

  name                   = var.registry_name
  subscription_tier_slug = var.subscription_tier
  region                 = var.region
}

# Connect registry to DOKS clusters
resource "digitalocean_container_registry_docker_credentials" "this" {
  count       = var.create ? 1 : 0
  registry_name = digitalocean_container_registry.this[0].name
  write         = false
}
```

## 8. Environment Composition Pattern

### Shared Environment (dev/test/staging)

```hcl
# environments/shared/main.tf
locals {
  environment = "shared"
  project     = "field-booking"
  region      = "fra1"
}

# VPC
module "vpc" {
  source = "../../modules/vpc"

  vpc_name    = "${local.project}-${local.environment}"
  region      = local.region
  description = "VPC for shared dev/test/staging environments"
  ip_range    = "10.10.0.0/16"
}

# DOKS Cluster (shared across dev/test/staging via namespaces)
module "doks" {
  source = "../../modules/doks-cluster"

  cluster_name       = "${local.project}-${local.environment}"
  region             = local.region
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  enable_ha          = false  # Cost optimization for non-prod
  auto_upgrade       = true
  enable_autoscaling = true
  default_node_size  = "s-4vcpu-8gb"
  min_nodes          = 2
  max_nodes          = 4

  registry_integration = true

  maintenance_day        = "sunday"
  maintenance_start_time = "04:00"

  tags = ["environment:shared"]
}

# PostgreSQL (shared, separate schemas per service)
module "postgres" {
  source = "../../modules/managed-postgres"

  cluster_name       = "${local.project}-${local.environment}-pg"
  region             = local.region
  postgres_version   = "16"
  size               = "db-s-1vcpu-2gb"
  node_count         = 1
  vpc_id             = module.vpc.vpc_id
  create_read_replica = false  # No replica needed for non-prod

  firewall_rules = [
    { type = "k8s", value = module.doks.cluster_id }
  ]

  tags = ["environment:shared"]
}

# Redis
module "redis" {
  source = "../../modules/managed-redis"

  cluster_name   = "${local.project}-${local.environment}-redis"
  region         = local.region
  redis_version  = "7"
  size           = "db-s-1vcpu-2gb"
  node_count     = 1
  vpc_id         = module.vpc.vpc_id

  firewall_rules = [
    { type = "k8s", value = module.doks.cluster_id }
  ]

  tags = ["environment:shared"]
}
```

### Production Environment

```hcl
# environments/production/main.tf
locals {
  environment = "production"
  project     = "field-booking"
  region      = "fra1"
}

module "vpc" {
  source = "../../modules/vpc"

  vpc_name    = "${local.project}-${local.environment}"
  region      = local.region
  description = "VPC for production environment"
  ip_range    = "10.20.0.0/16"
}

module "doks" {
  source = "../../modules/doks-cluster"

  cluster_name       = "${local.project}-${local.environment}"
  region             = local.region
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  enable_ha          = true   # HA for production
  auto_upgrade       = true
  surge_upgrade      = true
  enable_autoscaling = true
  default_node_size  = "s-4vcpu-8gb"
  min_nodes          = 3
  max_nodes          = 6

  # Dedicated observability node pool
  additional_node_pools = {
    observability = {
      name       = "observability"
      size       = "s-2vcpu-4gb"
      auto_scale = true
      min_nodes  = 1
      max_nodes  = 2
      labels     = { "workload" = "observability" }
      taints = [{
        key    = "dedicated"
        value  = "observability"
        effect = "NoSchedule"
      }]
    }
  }

  registry_integration = true

  maintenance_day        = "sunday"
  maintenance_start_time = "03:00"

  tags = ["environment:production"]
}

module "postgres" {
  source = "../../modules/managed-postgres"

  cluster_name        = "${local.project}-${local.environment}-pg"
  region              = local.region
  postgres_version    = "16"
  size                = "db-s-1vcpu-2gb"
  node_count          = 1
  vpc_id              = module.vpc.vpc_id
  create_read_replica = true  # Read replica for analytics

  firewall_rules = [
    { type = "k8s", value = module.doks.cluster_id }
  ]

  tags = ["environment:production"]
}

module "redis" {
  source = "../../modules/managed-redis"

  cluster_name   = "${local.project}-${local.environment}-redis"
  region         = local.region
  redis_version  = "7"
  size           = "db-s-1vcpu-2gb"
  node_count     = 1
  vpc_id         = module.vpc.vpc_id

  firewall_rules = [
    { type = "k8s", value = module.doks.cluster_id }
  ]

  tags = ["environment:production"]
}
```

## 9. Kubernetes Provider Integration

### Two-Stage Apply Pattern (DigitalOcean Recommended)

Never create DOKS cluster and deploy Kubernetes resources in the same module. Use data sources to reference existing clusters:

```hcl
# Stage 1: Infrastructure (environments/production/main.tf)
# Creates DOKS, databases, VPC, etc.

# Stage 2: Kubernetes resources (separate apply or separate module)
data "digitalocean_kubernetes_cluster" "this" {
  name = "field-booking-production"
}

provider "kubernetes" {
  host  = data.digitalocean_kubernetes_cluster.this.endpoint
  token = data.digitalocean_kubernetes_cluster.this.kube_config[0].token
  cluster_ca_certificate = base64decode(
    data.digitalocean_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  )
}

provider "helm" {
  kubernetes {
    host  = data.digitalocean_kubernetes_cluster.this.endpoint
    token = data.digitalocean_kubernetes_cluster.this.kube_config[0].token
    cluster_ca_certificate = base64decode(
      data.digitalocean_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
    )
  }
}
```

### Namespace Management

```hcl
# Namespaces for shared cluster
resource "kubernetes_namespace" "environments" {
  for_each = toset(["dev", "test", "staging"])

  metadata {
    name = each.value
    labels = {
      environment  = each.value
      managed_by   = "terraform"
      project      = "field-booking"
      istio_inject = each.value == "staging" ? "enabled" : "disabled"
    }
  }
}
```

### Helm Release Pattern (Observability Stack)

```hcl
resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.nginx_ingress_version
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [
    file("${path.module}/../../kubernetes/helm-values/nginx-ingress-values.yaml")
  ]

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-name"
    value = "${var.project}-${var.environment}-lb"
  }
}

resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.prometheus_stack_version
  namespace        = "monitoring"
  create_namespace = true

  values = [
    file("${path.module}/../../kubernetes/helm-values/prometheus-values.yaml")
  ]
}
```

## 10. CI/CD Pipeline Pattern (GitHub Actions)

### Terraform Plan on PR

```yaml
# .github/workflows/terraform-shared.yml
name: "Terraform Shared Environment"

on:
  pull_request:
    paths:
      - 'environments/shared/**'
      - 'modules/**'
  push:
    branches: [main]
    paths:
      - 'environments/shared/**'
      - 'modules/**'

env:
  TF_VERSION: "1.9.0"
  WORKING_DIR: "environments/shared"

jobs:
  plan:
    name: "Terraform Plan"
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init
        working-directory: ${{ env.WORKING_DIR }}

      - name: Terraform Validate
        run: terraform validate
        working-directory: ${{ env.WORKING_DIR }}

      - name: Terraform Plan
        id: plan
        run: terraform plan -no-color -out=tfplan
        working-directory: ${{ env.WORKING_DIR }}

      - name: Post Plan to PR
        uses: actions/github-script@v7
        with:
          script: |
            const output = `#### Terraform Plan 📖
            \`\`\`
            ${{ steps.plan.outputs.stdout }}
            \`\`\`
            *Pushed by: @${{ github.actor }}*`;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })

  apply:
    name: "Terraform Apply"
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: shared  # Requires manual approval for production
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init
        working-directory: ${{ env.WORKING_DIR }}

      - name: Terraform Apply
        run: terraform apply -auto-approve
        working-directory: ${{ env.WORKING_DIR }}
```

### Production Requires Manual Approval

```yaml
# .github/workflows/terraform-production.yml
# Same structure but with:
#   environment: production  (requires manual approval in GitHub settings)
#   paths filter: 'environments/production/**'
```

## 11. Security Best Practices

### Never Hardcode Secrets

```hcl
# ✅ Use variables with sensitive flag
variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "spaces_access_id" {
  description = "Spaces access key ID"
  type        = string
  sensitive   = true
}

variable "spaces_secret_key" {
  description = "Spaces secret access key"
  type        = string
  sensitive   = true
}

# ❌ Never hardcode tokens
provider "digitalocean" {
  token = "dop_v1_abc123..."
}
```

### Sensitive Outputs

```hcl
output "database_password" {
  description = "The password for the database cluster"
  value       = digitalocean_database_cluster.this[0].password
  sensitive   = true
}

output "database_uri" {
  description = "The connection URI for the database"
  value       = digitalocean_database_cluster.this[0].uri
  sensitive   = true
}
```

### Database Firewall Rules

Always restrict database access to known sources:

```hcl
# ✅ Restrict to DOKS cluster only
resource "digitalocean_database_firewall" "this" {
  cluster_id = digitalocean_database_cluster.this[0].id

  rule {
    type  = "k8s"
    value = digitalocean_kubernetes_cluster.this[0].id
  }
}

# ❌ Never allow all IPs
resource "digitalocean_database_firewall" "this" {
  cluster_id = digitalocean_database_cluster.this[0].id
  rule {
    type  = "ip_addr"
    value = "0.0.0.0/0"
  }
}
```

### VPC Isolation

All managed services MUST be placed in the VPC:

```hcl
resource "digitalocean_database_cluster" "this" {
  # ...
  private_network_uuid = digitalocean_vpc.this.id  # Always set
}

resource "digitalocean_kubernetes_cluster" "this" {
  # ...
  vpc_uuid = digitalocean_vpc.this.id  # Always set
}
```

## 12. Code Quality & Validation

### Terraform Validate

Run `terraform validate` in CI before plan:

```bash
terraform init -backend=false
terraform validate
```

### TFLint Configuration

```hcl
# .tflint.hcl
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}
```

### Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint
      - id: terraform_docs
```

## 13. Quick Reference — Decision Rules

| When you need to... | Do this |
|---------------------|---------|
| Create a new resource type | Create a resource module in `modules/` with main.tf, variables.tf, outputs.tf, versions.tf |
| Add a resource to an environment | Call the module from `environments/<env>/main.tf` |
| Share data between environments | Use `terraform_remote_state` data source |
| Make a resource optional | Add `create` boolean variable, use `count = var.create ? 1 : 0` |
| Access a conditional resource output | Use `try(resource.this[0].attribute, default)` |
| Name a cloud resource | Use dashes: `"fb-prod-postgres"` |
| Name a Terraform identifier | Use underscores: `resource "type" "primary_database" {}` |
| Store state | DigitalOcean Spaces with S3-compatible backend |
| Deploy K8s resources | Separate Terraform apply from cluster creation, use data sources |
| Install Helm charts | Use `helm_release` resource with external values files |
| Restrict database access | Always use `digitalocean_database_firewall` with `type = "k8s"` |
| Place resources in network | Always set `vpc_uuid` / `private_network_uuid` |
| Handle secrets | Use `sensitive = true` on variables and outputs, never hardcode |
| Run CI/CD | Post `terraform plan` as PR comment, require approval for apply |
| Validate code | `terraform fmt`, `terraform validate`, TFLint, pre-commit hooks |
| Version pin providers | Use `~>` pessimistic constraint (e.g., `~> 2.75`) |
| Version pin Terraform | Use `required_version = ">= 1.5.0"` |
| Tag resources | Always include `managed-by:terraform`, `project:field-booking`, `environment:<env>` |

## 14. DigitalOcean Resource Reference

### Droplet Sizes for DOKS Node Pools

| Size Slug | vCPUs | RAM | Use Case |
|-----------|-------|-----|----------|
| `s-2vcpu-4gb` | 2 | 4GB | Dev/test minimal |
| `s-4vcpu-8gb` | 4 | 8GB | Production workers, shared cluster |
| `s-2vcpu-2gb` | 2 | 2GB | Observability dedicated pool |

### Database Sizes

| Size Slug | vCPUs | RAM | Use Case |
|-----------|-------|-----|----------|
| `db-s-1vcpu-1gb` | 1 | 1GB | Dev/test |
| `db-s-1vcpu-2gb` | 1 | 2GB | Production (as per requirements) |
| `db-s-2vcpu-4gb` | 2 | 4GB | Future scaling |

### Regions

| Slug | Location | Use |
|------|----------|-----|
| `fra1` | Frankfurt, Germany | Primary (all environments) |

### Container Registry Tiers

| Tier | Storage | Price |
|------|---------|-------|
| `starter` | 500MB | Free |
| `basic` | 5GB | $5/mo |
| `professional` | 50GB | $12/mo |

## References

- [antonbabenko/terraform-best-practices](https://github.com/antonbabenko/terraform-best-practices) — Naming, structure, key concepts
- [Terraform Best Practices Book](https://www.terraform-best-practices.com/) — Code structure, orchestration
- [gruntwork-io/terragrunt-infrastructure-modules-example](https://github.com/gruntwork-io/terragrunt-infrastructure-modules-example) — Monorepo vs polyrepo, folder structure
- [terraform-aws-modules/terraform-aws-vpc](https://github.com/terraform-aws-modules/terraform-aws-vpc) — Module design patterns (4.5k stars)
- [terraform-aws-modules/terraform-aws-eks](https://github.com/terraform-aws-modules/terraform-aws-eks) — Kubernetes module patterns (4.2k stars)
- [do-community/terraform-sample-digitalocean-architectures](https://github.com/do-community/terraform-sample-digitalocean-architectures) — DO-specific patterns
- [terraform-do-modules](https://github.com/terraform-do-modules) — DO module collection (CloudDrove)
- [DigitalOcean Terraform Provider Docs](https://docs.digitalocean.com/reference/terraform/) — Official resource reference
- [poseidon/typhoon](https://github.com/poseidon/typhoon) — Multi-cloud Kubernetes with Terraform (1.9k stars)

---
*Content rephrased for compliance with licensing restrictions. Original sources cited above.*
