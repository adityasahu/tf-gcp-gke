variable "project_id" {
  description = "The project id to deploy Jenkins on GKE"
}

variable "region" {
  description = "The GCP region to deploy instances into"
  default     = "us-east4"
}

variable "zones" {
  description = "The GCP zone to deploy gke into"
  default     = ["us-east4-a"]
}

variable "tfstate_gcs_backend" {
  default = "gcp-terraform-315220-tfstate"
}


variable "jenkins_k8s_config" {
  description = "Name for the k8s secret required to configure k8s executers on Jenkins"
  default     = "jenkins-k8s-config"
}

# variable "github_username" {
#   description = "Github user/organization name where the terraform repo resides."
# }
#
# variable "github_token" {
#   description = "Github token to access repo."
# }
#
# variable "github_repo" {
#   description = "Github repo name."
#   default     = "tf-gcp-gke"
# }
