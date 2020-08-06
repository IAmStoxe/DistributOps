# Setup the provider as AWS and supply the API Credentials
provider "aws" {
  region     = var.aws_region
  access_key = var.access_key
  secret_key = var.secret_key
}

# Create a temporary SSH key that will be
# shared across all created instances
resource "tls_private_key" "temp_key" {
  algorithm = "RSA"
  rsa_bits  = 4096

}

# Assign the created SSH key to an AWS key pair named "generated_key"
resource "aws_key_pair" "generated_key" {
  key_name   = "temp_key"
  public_key = tls_private_key.temp_key.public_key_openssh
}

# Specify our initialization instructions for each of the created servers
# - Supply the values for the variables we can reference in our script
data "template_file" "init" {
  count    = var.instance_count
  template = "${file("action_run.tpl")}"
  vars = {
    count      = count.index
    total      = var.instance_count
    s3_bucket  = random_id.s3.hex
    scan_list  = var.scan_list
    port_list  = var.port_list
    aws_region = var.aws_region
  }
}

# Create the IAM role to allow access to the EC2 API
# - Name "temp_role"
# - Allow EC2 api calls
resource "aws_iam_role" "temp_role" {
  name = "temp_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Create an IAM instance profile named "temp_profile"
# and assign the created "temp_role" to the profile
resource "aws_iam_instance_profile" "temp_profile" {
  name = "temp_profile"
  role = aws_iam_role.temp_role.name
}

# Create an IAM role policy named "temp_policy"
# - Assign the created "temp_role" to the policy
# - Add a policy to allow all S3 api commands
resource "aws_iam_role_policy" "temp_policy" {
  name = "temp_policy"
  role = aws_iam_role.temp_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

# Create a new aws ec2 instance named "vm-ubuntu"
# - Based off the supplied ami
# - Set the type of instance to t2.micro
# - Assign the created SSH key to the resource
# - Assign the subnet on which our resource will reside
# - Assign VPC security group ids
resource "aws_instance" "vm-ubuntu" {
  lifecycle {
    ignore_changes = [
      instance_type,
    ]
  }
  iam_instance_profile        = aws_iam_instance_profile.temp_profile.name
  count                       = var.instance_count
  user_data                   = element(data.template_file.init.*.rendered, count.index)
  ami                         = "ami-04b9e92b5572fa0d1" # Replace with AMI from your region if necessary
  instance_type               = "t2.micro"
  key_name                    = "temp_key"
  associate_public_ip_address = true
  source_dest_check           = false
  vpc_security_group_ids      = [aws_security_group.sg-ubuntu.id]
  subnet_id                   = "subnet-XXXXXXXXXXXX"
}

# Create a random ID for our S3 container name the variable "s3"
resource "random_id" "s3" {
  byte_length = 8
}

# Create our S3 bucket and name it "scanning_storage"
# - Assign the name of bucket to our random_id we created
# - Set access to private
resource "aws_s3_bucket" "scanning_storage" {
  bucket        = random_id.s3.hex
  force_destroy = true
  acl           = "private"
}

# Create a new object to upload to the S3 bucket
# This will contain our initial data that will goto all servers
resource "aws_s3_bucket_object" "object" {
  bucket     = random_id.s3.hex
  key        = var.scan_list
  source     = var.scan_list
  depends_on = [aws_s3_bucket.scanning_storage]
}

# Create the security group and name it "sg-ubuntu"
# - Assign it to our VPC
# - Allow ingress from all ports
# - Allow egress to all ports and IPs
resource "aws_security_group" "sg-ubuntu" {
  name        = "sg_${var.host_name}"
  description = "sg-${var.host_name}"
  vpc_id      = "vpc-03ff99a530dc3dbd8"
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.allow_ingress_from]
  }
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create this resource so we can initiate the checks for completion
# on all of the created servers
resource "null_resource" "cluster" {
  # Changes to any instance of the cluster requires re-provisioning

  triggers = {
    cluster_instance_ids = "${var.instance_count - 1}"
  }

  # Bootstrap script can run on any instance of the cluster
  # So we just choose the last one in this case
  # and wait for it to finish executing and terminate.
  connection {
    host        = element(aws_instance.vm-ubuntu.*.public_ip, var.instance_count - 1)
    user        = "ubuntu"
    private_key = tls_private_key.temp_key.private_key_pem
  }

  provisioner "remote-exec" {

    # Script run on each container waiting for it to complete.
    inline = [
      "cloud-init status --wait",
    ]

  }
}
