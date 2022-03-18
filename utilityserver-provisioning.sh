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

duo_ikey=$1
duo_skey=$2
duo_api_host=$3
selfip_internal=$4
bigip_radius_secret=$5
ldaprootpw_hashed=$6
orjan_password=$7
binddnuserpw_hashed=$8

#Input troubleshooting
#echo $duo_intkey $duo_seckey $duo_apihost $selfip_internal $bigip_radius_secret $ldaprootpw_hashed

#--------Duo auth proxy install and config-----------

yum install gcc make libffi-devel perl zlib-devel diffutils selinux-policy-devel -y
wget --content-disposition https://dl.duosecurity.com/duoauthproxy-latest-src.tgz
tar xzf duoauthproxy-*
duodir=$(ls -d */)
cd $duodir
make
sudo ./duoauthproxy-build/install --install-dir /opt/duoauthproxy --service-user duo_authproxy_svc --log-group duo_authproxy_grp --create-init-script yes --enable-selinux=yes

cat << EOF > /home/orjan/duo-files
Duo config file
/opt/duoauthproxy/conf/authproxy.cfg

Duo log file
/opt/duoauthproxy/log/authproxy.log
EOF

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
port=1812
radius_secret_1=$bigip_radius_secret

[radius_server_duo_only2]
ikey=$duo_ikey
skey=$duo_skey
api_host=$duo_api_host
failmode=safe
radius_ip_1=$selfip_internal
port=1337
radius_secret_1=$bigip_radius_secret
EOF

/opt/duoauthproxy/bin/authproxyctl start

#------OpenLDAP install and config--------
#Based on https://computingforgeeks.com/install-configure-openldap-server-centos/

echo ""
echo ""
echo "---------Starting LDAP server install---------"
echo ""

cd ..

echo ""
echo "---------sudo dnf install wget vim......---------"
sudo dnf install wget vim cyrus-sasl-devel libtool-ltdl-devel openssl-devel libdb-devel make libtool autoconf  tar gcc perl perl-devel -y

echo ""
echo "---------sudo tee /etc/yum.repos.d/epel-el7.repo---------"
sudo tee /etc/yum.repos.d/epel-el7.repo<<EOF
[epel-el7]
name=Extra Packages for Enterprise Linux 7 - x86_64
baseurl=https://dl.fedoraproject.org/pub/epel/7/x86_64/
enabled=0
gpgcheck=0
EOF

echo ""
echo "------------------"
sudo dnf --enablerepo=epel-el7 install wiredtiger wiredtiger-devel -y

echo ""
echo "--------Misc preparation----------"
sudo useradd -r -M -d /var/lib/openldap -u 55 -s /usr/sbin/nologin ldap
VER=2.6.1
wget https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-$VER.tgz
tar xzf openldap-$VER.tgz
sudo mv openldap-$VER /opt
cd /opt/openldap-$VER

echo ""
echo "--------configure----------"
sudo ./configure --prefix=/usr --sysconfdir=/etc --disable-static \
--enable-debug --with-tls=openssl --with-cyrus-sasl --enable-dynamic \
--enable-crypt --enable-spasswd --enable-slapd --enable-modules \
--enable-rlookups --enable-backends=mod --disable-ndb --disable-sql \
--disable-shell --disable-bdb --disable-hdb --enable-overlays=mod

echo ""
echo "---------sudo make depend---------"
sudo make depend

echo ""
echo "---------sudo make---------"
sudo make

echo ""
echo "---------sudo make install---------"
sudo make install

echo ""
echo "---------Making folders and setting rights---------"
sudo mkdir /var/lib/openldap /etc/openldap/slapd.d
sudo chown -R ldap:ldap /var/lib/openldap
sudo chown root:ldap /etc/openldap/slapd.conf
sudo chmod 640 /etc/openldap/slapd.conf

echo ""
echo "---------copying schema---------"
sudo cp /usr/share/doc/sudo/schema.OpenLDAP  /etc/openldap/schema/sudo.schema
sudo su -

echo ""
echo "---------Starting LDAP server configuration---------"

cat << 'EOL' > /etc/openldap/schema/sudo.ldif
dn: cn=sudo,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: sudo
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.1 NAME 'sudoUser' DESC 'User(s) who may  run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.2 NAME 'sudoHost' DESC 'Host(s) who may run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.3 NAME 'sudoCommand' DESC 'Command(s) to be executed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.4 NAME 'sudoRunAs' DESC 'User(s) impersonated by sudo (deprecated)' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.5 NAME 'sudoOption' DESC 'Options(s) followed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.6 NAME 'sudoRunAsUser' DESC 'User(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.7 NAME 'sudoRunAsGroup' DESC 'Group(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcObjectClasses: ( 1.3.6.1.4.1.15953.9.2.1 NAME 'sudoRole' SUP top STRUCTURAL DESC 'Sudoer Entries' MUST ( cn ) MAY ( sudoUser $ sudoHost $ sudoCommand $ sudoRunAs $ sudoRunAsUser $ sudoRunAsGroup $ sudoOption $ description ) )
EOL

sudo mv /etc/openldap/slapd.ldif /etc/openldap/slapd.ldif.bak

cat << 'EOL' > /etc/openldap/slapd.ldif
dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: /var/lib/openldap/slapd.args
olcPidFile: /var/lib/openldap/slapd.pid

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulepath: /usr/libexec/openldap
olcModuleload: back_mdb.la

include: file:///etc/openldap/schema/core.ldif
include: file:///etc/openldap/schema/cosine.ldif
include: file:///etc/openldap/schema/nis.ldif
include: file:///etc/openldap/schema/inetorgperson.ldif
include: file:///etc/openldap/schema/sudo.ldif

dn: olcDatabase=frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: frontend
olcAccess: to dn.base="cn=Subschema" by * read
olcAccess: to * 
  by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage 
  by * none

dn: olcDatabase=config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: config
olcRootDN: cn=config
olcAccess: to * 
  by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage 
  by * none
EOL

sudo slapadd -n 0 -F /etc/openldap/slapd.d -l /etc/openldap/slapd.ldif -u
sudo slapadd -n 0 -F /etc/openldap/slapd.d -l /etc/openldap/slapd.ldif
sudo chown -R ldap:ldap /etc/openldap/slapd.d

cat << 'EOL' > /etc/systemd/system/slapd.service
[Unit]
Description=OpenLDAP Server Daemon
After=syslog.target network-online.target
Documentation=man:slapd
Documentation=man:slapd-mdb

[Service]
Type=forking
PIDFile=/var/lib/openldap/slapd.pid
Environment="SLAPD_URLS=ldap:/// ldapi:/// ldaps:///"
Environment="SLAPD_OPTIONS=-F /etc/openldap/slapd.d"
ExecStart=/usr/libexec/slapd -u ldap -g ldap -h ${SLAPD_URLS} $SLAPD_OPTIONS

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable --now slapd
cat << 'EOL' > rootdn.ldif
dn: olcDatabase=mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: mdb
olcDbMaxSize: 42949672960
olcDbDirectory: /var/lib/openldap
olcSuffix: dc=ldapmaster,dc=orbalabs,dc=local
olcRootDN: cn=admin,dc=ldapmaster,dc=orbalabs,dc=local
EOL

cat << EOL >> rootdn.ldif
olcRootPW: $ldaprootpw_hashed
EOL

cat << 'EOL' >> rootdn.ldif
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn pres,eq,approx,sub
olcDbIndex: mail pres,eq,sub
olcDbIndex: objectClass pres,eq
olcDbIndex: loginShell pres,eq
olcDbIndex: sudoUser,sudoHost pres,eq
olcAccess: to attrs=userPassword,shadowLastChange,shadowExpire
  by self write
  by anonymous auth
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage 
  by dn.subtree="ou=system,dc=ldapmaster,dc=orbalabs,dc=local" read
  by * none
olcAccess: to dn.subtree="ou=system,dc=ldapmaster,dc=orbalabs,dc=local" by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none
olcAccess: to dn.subtree="dc=ldapmaster,dc=orbalabs,dc=local" by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by users read 
  by * none
EOL

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f rootdn.ldif

cat << 'EOL' > basedn.ldif
dn: dc=ldapmaster,dc=orbalabs,dc=local
objectClass: dcObject
objectClass: organization
objectClass: top
o: orbalabs
dc: ldapmaster

dn: ou=groups,dc=ldapmaster,dc=orbalabs,dc=local
objectClass: organizationalUnit
objectClass: top
ou: groups

dn: ou=people,dc=ldapmaster,dc=orbalabs,dc=local
objectClass: organizationalUnit
objectClass: top
ou: people
EOL

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f basedn.ldif

cat << 'EOL' > users.ldif
dn: uid=orjan,ou=people,dc=ldapmaster,dc=orbalabs,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: orjan
cn: orjan
sn: Orjan
loginShell: /bin/bash
uidNumber: 10000
gidNumber: 10000
homeDirectory: /home/orjan
shadowMax: 60
shadowMin: 1
shadowWarning: 7
shadowInactive: 7
shadowLastChange: 0

dn: cn=orjan,ou=groups,dc=ldapmaster,dc=orbalabs,dc=local
objectClass: posixGroup
cn: orjan
gidNumber: 10000
memberUid: orjan
EOL

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f users.ldif
sudo ldappasswd -H ldapi:/// -Y EXTERNAL -s $orjan_password "uid=orjan,ou=people,dc=ldapmaster,dc=orbalabs,dc=local"

cat << 'EOL' > bindDNuser.ldif
dn: ou=system,dc=ldapmaster,dc=orbalabs,dc=local
objectClass: organizationalUnit
objectClass: top
ou: system

dn: cn=readonly,ou=system,dc=ldapmaster,dc=orbalabs,dc=local
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: readonly
EOL

cat << EOL >> bindDNuser.ldif
userPassword: $binddnuserpw_hashed
EOL

cat << 'EOL' >> bindDNuser.ldif
description: Bind DN user for LDAP Operations
EOL

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f bindDNuser.ldif