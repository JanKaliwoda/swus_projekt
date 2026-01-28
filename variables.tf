variable "gcp_project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "project-3038c4a4-b45e-4552-a13" 
}

variable "gcp_zone" {
  description = "The GCP zone - Primary Cluster"
  type        = string
  default     = "europe-west3-a"
}

variable "gcp_zone_secondary" {
  description = "The GCP zone - Secondary Cluster (Phase III)"
  type        = string
  default     = "europe-west3-b"
}