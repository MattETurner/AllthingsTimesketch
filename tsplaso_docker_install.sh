#!/bin/bash
# Description: This helper script will bring up Timesketch, Kibana (separate) and Plaso dockerised versions for rapid deployment. Further, it will set up InsaneTechnologies elastic pipelines so that relevant embedded fields can be extracted and mapped to fields in ES.
# Tested on Ubuntu 22.04 LTS Server Edition
# Created by Janantha Marasinghe
# Modified by Matthew Turner, 20241108
#
# Usage: sudo ./tsplaso_docker_install.sh
#
# CONSTANTS
# ---------------------------------------
#Setting default user creds
USER1_NAME=analyst
USER1_PASSWORD=$(openssl rand -base64 12)

# Domain Name - change this / Used for certbot registration of active TLD [case sensitive]
DOMAIN_NAME=yourdomain.TLD

# DATA DIRS
CASES_DIR="/cases"
DATA_DIR="/data"

# ---------------------------------------

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
sudo echo \
"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
# Install all pre-required Linux packages
sudo apt-get update
sudo apt-get install curl apt-transport-https ca-certificates curl gnupg lsb-release unzip unrar docker-ce docker-ce-cli containerd.io python3-pip docker-compose -y

# change directory to where we will install timesketch
cd /opt

# Download and install Timesketch
sudo curl -s -O https://raw.githubusercontent.com/google/timesketch/master/contrib/deploy_timesketch.sh
sudo chmod 755 deploy_timesketch.sh
## if /opt/timesketch already exists, this will fail

if [ -d "/opt/timesketch" ]; then
    read -p "/opt/timesketch already exists. Do you want to delete it? (y/n) " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "Exiting installation."
        exit 1
    fi
    sudo rm -rf /opt/timesketch
fi

sudo ./deploy_timesketch.sh
cd /opt/timesketch

 
# Download docker version of plaso
sudo docker pull log2timeline/plaso

# Prep directories 
if [ -d "$CASES_DIR" ]; then
    read -p "$CASES_DIR already exists. Do you want to delete it? (y/n) " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "Exiting installation."
        exit 1
    fi
    sudo rm -rf $CASES_DIR
fi

if [ -d "$DATA_DIR" ]; then
    read -p "$DATA_DIR already exists. Do you want to delete it? (y/n) " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "Exiting installation."
        exit 1
    fi
    sudo rm -rf $DATA_DIR
fi

sudo mkdir $CASES_DIR
sudo mkdir $DATA_DIR
sudo chmod -R 777 $CASES_DIR
sudo chmod -R 777 $DATA_DIR

# Native Install Commented Out
#add-apt-repository ppa:gift/stable -y
#apt-get update
#apt-get install plaso-tools -y

# Install Timesketch import client to assist with larger plaso uploads
pip3 install timesketch-import-client

# Download the latest tags file from MattETurner forked repo
sudo wget -Nq https://raw.githubusercontent.com/MattETurner/AllthingsTimesketch/master/tags.yaml -O /opt/timesketch/etc/timesketch/tags.yaml

#Increase the CSRF token time limit
# OLD --> sudo echo -e '\nWTF_CSRF_TIME_LIMIT = 3600' >> /opt/timesketch/etc/timesketch/timesketch.conf
sudo sh -c "echo '\nWTF_CSRF_TIME_LIMIT = 3600' >> /opt/timesketch/etc/timesketch/timesketch.conf"

sudo docker-compose up -d

# Create directories to hold the self-signed cert and the key 
sudo mkdir -p /opt/timesketch/ssl/certs
sudo mkdir -p /opt/timesketch/ssl/private

sudo chmod 722 /opt/timesketch/ssl/certs
sudo chmod 722 /opt/timesketch/ssl/private

# Ask user if this will be a self-signed cert installation
read -p "Will this be a self-signed cert installation? (y/n) " answer

if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
    # Generate a local self-signed certificate for HTTPS operations
    openssl req -x509 -out /opt/timesketch/ssl/certs/fullchain.pem -keyout /opt/timesketch/ssl/private/privkey.pem -newkey rsa:2048 -nodes -sha256 -subj '/CN=localhost' -extensions EXT -config <( printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
else
    # Check if certbot is installed and a certificate exists
    if [ -x "$(command -v certbot)" ] && [ -f "/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem" ]; then
        # Copy the cert and key to the appropriate directories
        sudo cp /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem /opt/timesketch/ssl/certs/
        sudo cp /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem /opt/timesketch/ssl/private/
    else
        echo "Certbot is not installed or a certificate does not exist. Please install and configure certbot before continuing."
        exit 1
    fi
fi

sudo chmod 700 /opt/timesketch/ssl/certs
sudo chmod 700 /opt/timesketch/ssl/private
#Restrict private key permissions
sudo chmod 600 /opt/timesketch/ssl/private/privkey.pem

# Download the custom nginx configuration
# Nginx modified to add the self-signed cert configuration
sudo wget -Nq https://raw.githubusercontent.com/MattETurner/AllthingsTimesketch/master/nginx.conf -O /opt/timesketch/etc/nginx.conf

# Download the custom docker-compose configuration
# docker-compose modified to add the volume containing ssl cert and key for nginx
sudo wget -Nq https://raw.githubusercontent.com/MattETurner/AllthingsTimesketch/master/docker-compose.yml -O /opt/timesketch/docker-compose.yml

# Download the loop.sh file for the plaso container
sudo wget -Nq https://raw.githubusercontent.com/MattETurner/AllthingsTimesketch/master/loop.sh -O /opt/timesketch/loop.sh

# Start all docker containers to make the changes effective
sudo docker-compose down
sudo docker-compose up -d

# Giving few seconds for the docker instances to poweron 
sleep 15

# Create the first user account
sudo docker-compose exec timesketch-web tsctl create-user $USER1_NAME --password $USER1_PASSWORD

echo -e "************************************************\n"
printf "Timesketch User Details: \n"
echo -e "\n"
printf "User name is $USER1_NAME and the password is $USER1_PASSWORD\n"
echo -e "\n"
echo -e "************************************************\n"
echo -e "************************************************\n"
