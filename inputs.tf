variable "bucket_name" {
  description = "The name of the S3 bucket to create"
  type        = string
}

variable "primary_fqdn" {
  description = "The primary FQDN for the website"
  type        = string
}

variable "alternative_fqdn" {
  description = "The alternative FQDN for the website (needs to be in the same zone as the primary FQDN)"
  type        = string
  default = ""
}

variable "dns_zone_name" {
  description = "The name of the DNS zone to create"
  type        = string
}