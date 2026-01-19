variable "gcp_project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "cedar-abacus-480412-e1" 
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