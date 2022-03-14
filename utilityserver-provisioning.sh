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

cat << EOF > /opt/duoauthproxy/conf/authproxy.cfg
; Complete documentation about the Duo Auth Proxy can be found here:
; https://duo.com/docs/authproxy_reference

; NOTE: After any changes are made to this file the Duo Authentication Proxy
; must be restarted for those changes to take effect.

; MAIN: Include this section to specify global configuration options.
; Reference: https://duo.com/docs/authproxy_reference#main-section
;[main]


; CLIENTS: Include one or more of the following configuration sections.
; To configure more than one client configuration of the same type, append a
; number to the section name (e.g. [ad_client2])

;[ad_client]
;host=
;service_account_username=
;service_account_password=
;search_dn=


; SERVERS: Include one or more of the following configuration sections.
; To configure more than one server configuration of the same type, append a
; number to the section name (e.g. radius_server_auto1, radius_server_auto2)

;[radius_server_auto]
;ikey=
;skey=
;api_host=
;radius_ip_1=
;radius_secret_1=
;failmode=safe
;client=ad_client
;port=1812

[radius_server_duo_only]
ikey=$duo_ikey
skey=$duo_skey
api_host=$duo_api_host
failmode=safe
radius_ip_1=$selfip_internal
radius_secret_1=$bigip_radius_secret
EOF

/opt/duoauthproxy/bin/authproxyctl start