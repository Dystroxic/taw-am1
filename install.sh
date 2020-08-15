#!/bin/bash

#set some basic common variables
steam_home="/home/steam"
repo_url="https://github.com/Tirpitz93/TAW-Arma"
repo_dir="$steam_home/TAW-Arma"
#get the user (the user that called sudo)

# exit when any command fails
set -e

if [[ ! "$EUID" = 0 ]]; then
    echo "This script must be run as root/sudo" >&2; exit 1
fi

echo "For which battalion would you like to set up this server?
1] AM1
2] AM2"

read -p "Please enter 1 for AM1 or 2 for AM2 " -n 1 batt
# remove config directory
if [ -d "../config" ]
then
  rm -r ../config
fi
if [ "$batt" == '1' ]
 then
  echo "Loading AM1 config"
  #todo: add AM1 repo
  echo "AM1 has not been set up yet"
  exit 1
elif [ "$batt" == "2" ]
 then
      echo "loading AM2 Config"
      repo_url="https://github.com/Tirpitz93/AM2_config"

else
  echo "invalid selection"
  exit 1
fi

apt update
apt install software-properties-common psmisc git-all -y
user_name=$(pstree -lu -s $$ | grep --max-count=1 -o '([^)]*)' | head -n 1 | tr -d '()')
#add-apt-repository multiverse
echo "user name is $user_name"
if lsb_release -i | grep -q 'Debian'
then
  #if linide repo is not present add it
  if grep -q "deb http://mirrors.linode.com/debian stretch main non-free" /etc/apt/sources.list; then
    echo "deb http://mirrors.linode.com/debian stretch main non-free"  >> /etc/apt/sources.list
    echo "deb-src http://mirrors.linode.com/debian stretch main non-free" >> /etc/apt/sources.list

  fi
  # add contrib and non-free repos
  apt-add-repository contrib
  apt-add-repository non-free
elif lsb_release -i | grep -q 'Ubuntu'; then
  #if multiverse is not present add it
  if grep -q "deb http://archive.ubuntu.com/ubuntu xenial main universe multiverse" /etc/apt/sources.list
  then
    echo "deb http://archive.ubuntu.com/ubuntu xenial main universe multiverse" >>  /etc/apt/sources.list
    echo "deb http://archive.ubuntu.com/ubuntu xenial-updates main universe multiverse" >> /etc/apt/sources.list
    echo "deb http://archive.ubuntu.com/ubuntu xenial-security main universe multiverse" >> /etc/apt/sources.list
  fi
fi


dpkg --add-architecture i386
apt update -y
apt install lib32gcc1 net-tools dos2unix steamcmd npm apache2-utils nginx ufw python3-certbot-nginx unzip python3-pip jq -y
apt upgrade -y
id -u steam &>/dev/null || useradd -m steam

#install python libraries
pip3 install bs4
# Copy the ubuntu user's authorized keys over to the Steam user
# but only if it exists

mkdir -p "$steam_home/.ssh"
if  [ -f "/home/$user_name/.ssh/authorized_keys" ]
then
  cp "/home/$user_name/.ssh/authorized_keys" "$steam_home/.ssh/"
  chown -R steam:steam "$steam_home/.ssh"
  chmod 755 "$steam_home/.ssh"
  chmod 644 "$steam_home/.ssh/authorized_keys"
fi

# Open necessary firewall ports
ufw allow 80/tcp # HTTP
ufw allow 443/tcp # HTTPS
ufw allow 22/tcp # SSH
# Configure ingress ports for 10 game servers (2302-2306, 2312-2316, 2322-2326, etc.)
for (( i=0; i<10; i++ )); do
    ufw allow $(( i*10 + 2302 )):$(( i*10 + 2306 ))/udp
done

# Configure ARMA profile directory
sudo -u steam mkdir -p "$steam_home/arma-profiles"

# Clone the full repo under the Steam user (includes the web console as a submodule)
# If already cloned, pull updates instead
if [ ! -d "$repo_dir" ]; then
    sudo -u steam git clone --recursive "$repo_url" "$repo_dir"
else
    sudo -u steam git -C "$repo_dir" fetch --all
    sudo -u steam git -C "$repo_dir" reset --hard origin/master
    sudo -u steam git -C "$repo_dir" pull --recurse-submodules origin master
fi
pushd "$repo_dir"

sudo -u steam git clone $repo_url "$repo_dir/../config"
source ../config/config.sh

# Install the service file for the web console (replacing template fields as we go)
sed -e "s#\${repo_dir}#$repo_dir#"  "$repo_dir/arma3-web-console.service" >/etc/systemd/system/arma3-web-console.service

chmod 644 /etc/systemd/system/arma3-web-console.service
systemctl daemon-reload

# Configure nginx
# Remove any existing config files
rm -fr /etc/nginx/sites-enabled/*
# Copy the config file
#cp "$repo_dir/nginx.conf" /etc/nginx/sites-enabled/arma.conf
#install nginx config with template substitution
sed -e "s#\${domain}#$domain#" "$repo_dir/nginx.conf" >/etc/nginx/sites-enabled/arma.conf

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


##install cron job to update at 4 am every day
#write out current crontab
sudo -u steam crontab -l > mycron
#echo new cron into cron file
sed -e "s#\${repo_dir}#$repo_dir#" "$repo_dir/update.cron.template" >>mycron
#install new cron file
sudo -u steam crontab mycron
rm mycron

# Enable and start the web console service
systemctl enable arma3-web-console
systemctl restart arma3-web-console

# Set up nginx
systemctl enable nginx
systemctl restart nginx
