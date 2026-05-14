provider "aws" {
	region = "ap-south-1"
}


data "aws_ami" "ubuntu" {
	most_recent = true
	owners = ["099720109477"]
	
    	filter {
        	name   = "name"
        	values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
    	}
}
resource "aws_key_pair" "spot_key" {
  key_name   = "spot-key"
  public_key = file("~/.ssh/spot_key.pub")
}
resource "aws_security_group" "sg" {
  name        = "spot-sg"
  description = "Allow SSH and HTTP traffic"

  # Allow SSH from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP (needed for Task 10)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS (needed for Task 11)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (so the server can download Docker)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "spot_server" {
	ami = data.aws_ami.ubuntu.id
	instance_type = "t3.micro"
  key_name      = aws_key_pair.spot_key.key_name
  vpc_security_group_ids = [aws_security_group.sg.id]
	associate_public_ip_address = true 
	instance_market_options {
		market_type = "spot"
    spot_options {
      instance_interruption_behavior = "stop"
      spot_instance_type             = "persistent"
    }
	}
	tags = {
		Name = "Spot-Server"
		AutoStop = "18:00"
		AutoStart = "8:30"
	}
}

