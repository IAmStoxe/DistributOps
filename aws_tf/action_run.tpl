#!/bin/bash 

# Download pre-requisities
sudo apt update
sudo apt install git bmon build-essential -y
sudo apt-get install git gcc make libpcap-dev -yq

# Download masscan and build
git clone https://github.com/robertdavidgraham/masscan
cd masscan
make -j

# Install AWS CLi
sudo snap install aws-cli --classic
/snap/bin/aws s3 cp s3://${s3_bucket}/${scan_list} .

# Run masscan
sudo /masscan/bin/masscan -p${port_list} --open --rate 1000000000 -iL ${scan_list} --excludefile /masscan/data/exclude.conf -oB /masscan/results-${count}.masscan.bin --shard ${count}/${total} 2>&1 | tee /tmp/stdout.txt

# Copy the saved file to our s3 bucket
/snap/bin/aws s3 cp /masscan/results-${count}.masscan.bin s3://${s3_bucket}/results-${count}.masscan.bin 

