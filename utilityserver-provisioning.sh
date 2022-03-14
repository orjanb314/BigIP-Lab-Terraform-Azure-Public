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

yum install gcc make libffi-devel perl zlib-devel diffutils selinux-policy-devel -y
wget --content-disposition https://dl.duosecurity.com/duoauthproxy-latest-src.tgz
tar xzf duoauthproxy-*
duodir=$(ls -d */)
cd $duodir
make
sudo ./duoauthproxy-build/install --install-dir /opt/duoauthproxy --service-user duo_authproxy_svc --log-group duo_authproxy_grp --create-init-script yes --enable-selinux=yes