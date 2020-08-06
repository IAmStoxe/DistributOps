variable "aws_region" {
  description = "Region for the VPC"
  default     = "us-east-1"
}


variable "secret_key" {}
variable "access_key" {}


variable "allow_ingress_from" {
  description = "IP that will be allowed to access the Ubuntu host ie, x.x.x.x/x (your ip)"
}

variable "host_name" {
  description = "Host name to give server"
  default     = "ubuntu"
}

variable "instance_count" {
  default = 5
}

variable "scan_list" {
  description = "List of IP's to scan (Enter file name here - i.e. ips.txt) "
}

variable "port_list" {
  description = "The ports you wish to scan wish masscan (comma delimited, no spaces - i.e 80,443,8080,8888)"
}
