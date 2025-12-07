variable "gcp_project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
  default     = "cedar-abacus-480412-e1" # REPLACE WITH YOUR ACTUAL PROJECT ID
}

variable "gcp_zone" {
  description = "The GCP zone to deploy resources into (e.g., europe-west3-a)."
  type        = string
  default     = "europe-west3-a" # Choose a zone close to you
}