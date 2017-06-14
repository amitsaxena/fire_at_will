#!/bin/sh
sudo apt-get --assume-yes install apache2-utils && cd /tmp && wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb && sudo dpkg -i amazon-ssm-agent.deb && sudo systemctl start amazon-ssm-agent
