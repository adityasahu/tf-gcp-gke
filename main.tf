provider "google" {
  #credentials = file("gcp-terraform-315220-9b60d19595b2.json")
  project = "gcp-terraform-315220"
  region = var.region
}

resource "google_service_account" "default" {
  account_id   = "${var.project_id}-sa"
  display_name = "Service Account"
}

resource "google_container_cluster" "primary" {
  name     = "${var.project_id}-gke"
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  workload_identity_config {
  identity_namespace = "${var.project_id}.svc.id.goog"
  }

}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "${var.project_id}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-medium"

    workload_metadata_config {
     node_metadata = "GKE_METADATA_SERVER"
   }

    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = google_service_account.default.email
    oauth_scopes    = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# allow GKE to pull images from GCR
# resource "google_project_iam_member" "gke" {
#   project = var.project_id
#   role    = "roles/storage.objectViewer"
#
#   member = "serviceAccount:gcp-terraform-sa"
# }

resource "kubernetes_secret" "jenkins-secrets" {
  metadata {
    name = var.jenkins_k8s_config
  }
  data = {
    project_id          = var.project_id
    kubernetes_endpoint = "https://${google_container_cluster.primary.endpoint}"
    ca_certificate      = base64decode(
      google_container_cluster.primary.master_auth[0].cluster_ca_certificate,
    )
    jenkins_tf_ksa      = module.workload_identity.k8s_service_account_name
  }
}

resource "google_storage_bucket_iam_member" "tf-state-writer" {
  bucket = var.tfstate_gcs_backend
  role   = "roles/storage.admin"
  member = module.workload_identity.gcp_service_account_fqn
}

resource "google_project_iam_member" "jenkins-project" {
  project = var.project_id
  role    = "roles/editor"

  member = module.workload_identity.gcp_service_account_fqn

}


# Retrieve an access token as the Terraform runner
data "google_client_config" "provider" {}

provider "kubernetes" {
  host  = "https://${google_container_cluster.primary.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.primary.master_auth[0].cluster_ca_certificate,
  )
}

module "workload_identity" {
  source              = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  version             = "~> 7.0"
  project_id          = var.project_id
  name                = "wi-gke"
  namespace           = "default"
  use_existing_k8s_sa = false
}

provider "helm" {
  kubernetes {
    # load_config_file       = false
    cluster_ca_certificate = base64decode(
      google_container_cluster.primary.master_auth[0].cluster_ca_certificate,
    )
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.provider.access_token
  }
}

# resource "kubernetes_secret" "gh-secrets" {
#   metadata {
#     name = "github-secrets"
#   }
#   data = {
#     github_username = var.github_username
#     github_repo     = var.github_repo
#     github_token    = var.github_token
#   }
# }

module "gke_auth" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  version = "~> 9.1"

  project_id   = var.project_id
  cluster_name = "${var.project_id}-gke"
  location     = var.region
}

data "local_file" "helm_chart_values" {
  filename = "${path.module}/values.yaml"
}

resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.helm.sh/stable"
  chart      = "jenkins"
  # version    = "2.289.1"
  timeout    = 1200

  values = [data.local_file.helm_chart_values.content]

  depends_on = [
    kubernetes_secret.gh-secrets,
  ]
}
