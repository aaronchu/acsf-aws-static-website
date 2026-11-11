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
  default     = ""
}

variable "dns_zone_name" {
  description = "The name of the DNS zone to create"
  type        = string
}

variable "redirect_alternative_fqdn" {
  description = "301-redirect requests for alternative_fqdn to primary_fqdn instead of serving the site on both"
  type        = bool
  default     = false
}

variable "not_found_page_path" {
  description = "Path of the page to serve, with status 404, for missing objects (e.g. /404.html). Empty serves S3's 403 error."
  type        = string
  default     = ""
}

variable "browser_cache_control" {
  description = "Cache-Control header sent to browsers for objects that don't set their own (e.g. \"public, max-age=3600\"). Empty sends none."
  type        = string
  default     = ""
}
