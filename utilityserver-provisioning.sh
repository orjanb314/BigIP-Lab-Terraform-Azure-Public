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

duo_ikey=$1
duo_skey=$2
duo_api_host=$3
selfip_internal=$4
bigip_radius_secret=$5

echo $duo_intkey $duo_seckey $duo_apihost $selfip_internal $bigip_radius_secret

cat << EOF >> /opt/duoauthproxy/conf/authproxy.cfg

[radius_server_duo_only]
ikey=$duo_ikey
skey=$duo_skey
api_host=$duo_api_host
failmode=safe
radius_ip_1=$selfip_internal
radius_secret_1=$bigip_radius_secret
EOF
