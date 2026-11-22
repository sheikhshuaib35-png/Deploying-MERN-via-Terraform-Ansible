variable "aws_region" {
  description = "AWS Region in which to create the network and EC2 instances."
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Short prefix used for resource names and tags."
  type        = string
  default     = "travelmemory"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR range for the project VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR range for the public web subnet."
  type        = string
  default     = "10.40.1.0/24"
}

variable "private_subnet_cidr" {
  description = "IPv4 CIDR range for the private database subnet."
  type        = string
  default     = "10.40.2.0/24"
}

variable "admin_cidr" {
  description = "Administrator public IPv4 CIDR allowed to SSH to the web instance (use /32)."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && can(regex("/32$", var.admin_cidr))
    error_message = "admin_cidr must be a single valid IPv4 address ending in /32."
  }
}

variable "ssh_public_key" {
  description = "Contents of the SSH public key corresponding to the private key used by Ansible."
  type        = string

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp)", var.ssh_public_key))
    error_message = "ssh_public_key must contain a supported OpenSSH public key."
  }
}

variable "web_instance_type" {
  description = "EC2 instance type for the public Node.js/Nginx web server."
  type        = string
  default     = "t3.micro"
}

variable "database_instance_type" {
  description = "EC2 instance type for the private MongoDB server."
  type        = string
  default     = "t3.small"
}
