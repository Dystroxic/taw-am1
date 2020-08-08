#!/bin/bash

# exit when any command fails
set -e

if [[ ! "$EUID" = 0 ]]; then 
    echo "This script must be run as root/sudo" >&2; exit 1
fi

steam_home="/home/steam"
repo_url="https://github.com/Dystroxic/taw-am1.git"
repo_dir="$steam_home/taw-am1"
domain="am1.dystroxic.com"
email="dystroxic@taw.net"

add-apt-repository multiverse
dpkg --add-architecture i386
apt update -y
apt install lib32gcc1 net-tools steamcmd npm nginx python3-certbot-nginx unzip jq -y
apt upgrade -y
id -u steam &>/dev/null || useradd -m steam

# Copy the ubuntu user's authorized keys over to the Steam user
mkdir -p "$steam_home/.ssh"
cp /home/ubuntu/.ssh/authorized_keys "$steam_home/.ssh/"
chown -R steam:steam "$steam_home/.ssh"
chmod 755 "$steam_home/.ssh"
chmod 644 "$steam_home/.ssh/authorized_keys"

# Configure ARMA profile directory
sudo -u steam mkdir -p "$steam_home/arma-profiles"

# Clone the full repo under the Steam user (includes the web console as a submodule)
# If already cloned, pull updates instead
if [ ! -d "$repo_dir" ]; then
    sudo -u steam git clone --recursive "$repo_url" "$repo_dir"
else
    cd "$repo_dir" && sudo -u steam git pull --recurse-submodules
fi

# Install the service file for the web console
cp "$repo_dir/arma3-web-console.service" /etc/systemd/system/
chmod 644 /etc/systemd/system/arma3-web-console.service
systemctl daemon-reload

# Configure nginx
# Remove any existing config files
rm -fr /etc/nginx/sites-enabled/*
# Copy the config file
cp "$repo_dir/nginx.conf" /etc/nginx/sites-enabled/arma.conf
# Set the config file owner to root
chown -h root:root /etc/nginx/sites-enabled/arma.conf
# Ensure the nginx config file is valid
nginx -t

# Configure the new certificate
certbot --nginx --non-interactive --agree-tos --redirect --email "$email" --domains "$domain"

# Install dependencies for the web console
cd "$repo_dir/arma-server-web-admin"
sudo -u steam npm install

# Run the update script to download ARMA and the mods, and to configure the web console
sudo -u steam "$repo_dir/update.sh" -swv

# Enable and start the new service
systemctl enable arma3-web-console
systemctl start arma3-web-console

# Set up nginx
systemctl enable nginx
systemctl restart nginx
