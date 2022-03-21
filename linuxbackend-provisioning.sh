#!/bin/bash -x

mkdir -p  /var/log/cloud /config/cloud /var/config/rest/downloads

LOG_FILE=/var/log/cloud/startup-script.log
[[ ! -f $LOG_FILE ]] && touch $LOG_FILE || { echo "Run Only Once. Exiting"; exit; }
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a $LOG_FILE /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1

#Ubuntu
#sudo apt update
#sudo apt-get -y install apache2
#hostname=$(hostname)
#sudo sed -i "s/It works!/It works! ($hostname)/" /var/www/html/index.html
#sudo service apache2 start

#Centos
sudo dnf install httpd -y
#sudo firewall-cmd --permanent --add-service=https
#sudo firewall-cmd --reload
hostname=$(hostname)
sudo sed -i "s/Page<\/strong>/Page<\/strong> ($hostname)/" /usr/share/httpd/noindex/index.html
sudo systemctl start httpd