#. /vagrant/common.sh

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update

# Grizzly Goodness
sudo apt-get -y install ubuntu-cloud-keyring
echo "deb  http://ubuntu-cloud.archive.canonical.com/ubuntu precise-proposed/grizzly main" | sudo tee -a /etc/apt/sources.list.d/grizzly.list
sudo apt-get update

#sudo apt-get -y install

MY_IP=$(ifconfig eth1 | awk '/inet addr/ {split ($2,A,":"); print A[2]}')
MY_PRIV_IP=$(ifconfig eth2 | awk '/inet addr/ {split ($2,A,":"); print A[2]}')


# Must define your environment
#MYSQL_HOST=${CONTROLLER_HOST}
#GLANCE_HOST=${CONTROLLER_HOST}

# Define environment variables to contain the OpenStack Controller Public and Private IP for later use with Cinder
export OSCONTROLLER=$MY_IP
export OSCONTROLLER_P=$MY_PRIV_IP

# MySQL
export MYSQL_HOST=$MY_IP
export MYSQL_ROOT_PASS=openstack
export MYSQL_DB_PASS=openstack

echo "mysql-server-5.5 mysql-server/root_password password $MYSQL_ROOT_PASS" | sudo debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password $MYSQL_ROOT_PASS" | sudo debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password seen true" | sudo debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again seen true" | sudo debconf-set-selections

###############################
# MySQL Install
###############################

sudo apt-get -y install mysql-server python-mysqldb

sudo sed -i "s/^bind\-address.*/bind-address = 0.0.0.0/g" /etc/mysql/my.cnf
sudo sed -i "s/^#max_connections.*/max_connections = 512/g" /etc/mysql/my.cnf

# Skip Name Resolve
echo "[mysqld]
skip-name-resolve" > /etc/mysql/conf.d/skip-name-resolve.cnf

sudo restart mysql

# Ensure root can do its job
mysql -u root --password=${MYSQL_ROOT_PASS} -h localhost -e "GRANT ALL ON *.* to root@\"localhost\" IDENTIFIED BY \"${MYSQL_ROOT_PASS}\" WITH GRANT OPTION;"
mysql -u root --password=${MYSQL_ROOT_PASS} -h localhost -e "GRANT ALL ON *.* to root@\"${MYSQL_HOST}\" IDENTIFIED BY \"${MYSQL_ROOT_PASS}\" WITH GRANT OPTION;"
mysql -u root --password=${MYSQL_ROOT_PASS} -h localhost -e "GRANT ALL ON *.* to root@\"%\" IDENTIFIED BY \"${MYSQL_ROOT_PASS}\" WITH GRANT OPTION;"

mysqladmin -uroot -p${MYSQL_ROOT_PASS} flush-privileges


###############################
# Keystone Install
###############################
sudo apt-get -y install keystone python-keyring

MYSQL_ROOT_PASS=openstack
MYSQL_KEYSTONE_PASS=openstack
mysql -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE keystone;'
mysql -uroot -p$MYSQL_ROOT_PASS -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%';"
mysql -uroot -p$MYSQL_ROOT_PASS -e "SET PASSWORD FOR 'keystone'@'%' = PASSWORD('$MYSQL_KEYSTONE_PASS');"

sudo sed -i "s#^connection.*#connection = mysql://keystone:openstack@${MYSQL_HOST}/keystone#" /etc/keystone/keystone.conf

sudo sed -i 's/^# admin_token.*/admin_token = ADMIN/' /etc/keystone/keystone.conf

sudo stop keystone
sudo start keystone

sudo keystone-manage db_sync

sudo apt-get -y install python-keystoneclient

export ENDPOINT=${MY_IP}
export SERVICE_TOKEN=ADMIN
export SERVICE_ENDPOINT=http://${ENDPOINT}:35357/v2.0

# admin role
keystone role-create --name admin

# Member role
keystone role-create --name Member

keystone tenant-create --name cookbook --description "Default Cookbook Tenant" --enabled true

TENANT_ID=$(keystone tenant-list | awk '/\ cookbook\ / {print $2}')

export PASSWORD=openstack
keystone user-create --name admin --tenant_id $TENANT_ID --pass $PASSWORD --email root@localhost --enabled true

TENANT_ID=$(keystone tenant-list | awk '/\ cookbook\ / {print $2}')

ROLE_ID=$(keystone role-list | awk '/\ admin\ / {print $2}')

USER_ID=$(keystone user-list | awk '/\ admin\ / {print $2}')

keystone user-role-add --user $USER_ID --role $ROLE_ID --tenant_id $TENANT_ID

# Create the user
PASSWORD=openstack
keystone user-create --name demo --tenant_id $TENANT_ID --pass $PASSWORD --email demo@localhost --enabled true

TENANT_ID=$(keystone tenant-list | awk '/\ cookbook\ / {print $2}')

ROLE_ID=$(keystone role-list | awk '/\ Member\ / {print $2}')

USER_ID=$(keystone user-list | awk '/\ demo\ / {print $2}')

# Assign the Member role to the demo user in cookbook
keystone user-role-add --user $USER_ID --role $ROLE_ID --tenant_id $TENANT_ID

# Cinder Block Storage Endpoint
keystone service-create --name volume --type volume --description 'Volume Service'

# OpenStack Compute Nova API Endpoint
keystone service-create --name nova --type compute --description 'OpenStack Compute Service'

# OpenStack Compute EC2 API Endpoint
keystone service-create --name ec2 --type ec2 --description 'EC2 Service'

# Keystone Identity Service Endpoint
keystone service-create --name keystone --type identity --description 'OpenStack Identity Service'

# Glance Image Service Endpoint
keystone service-create --name glance --type image --description 'OpenStack Image Service'

# Keystone OpenStack Identity Service
KEYSTONE_SERVICE_ID=$(keystone service-list | awk '/\ keystone\ / {print $2}')

PUBLIC="http://$ENDPOINT:5000/v2.0"
ADMIN="http://$ENDPOINT:35357/v2.0"
INTERNAL=$PUBLIC

keystone endpoint-create --region RegionOne --service_id $KEYSTONE_SERVICE_ID --publicurl $PUBLIC --adminurl $ADMIN --internalurl $INTERNAL

# Glance Image Service
GLANCE_SERVICE_ID=$(keystone service-list | awk '/\ glance\ / {print $2}')

PUBLIC="http://$ENDPOINT:9292"
ADMIN=$PUBLIC
INTERNAL=$PUBLIC

keystone endpoint-create --region RegionOne --service_id $GLANCE_SERVICE_ID --publicurl $PUBLIC --adminurl $ADMIN --internalurl $INTERNAL

# OpenStack Compute Nova API
NOVA_SERVICE_ID=$(keystone service-list | awk '/\ nova\ / {print $2}')

PUBLIC="http://$ENDPOINT:8774/v2/\$(tenant_id)s"
ADMIN=$PUBLIC
INTERNAL=$PUBLIC

keystone endpoint-create --region RegionOne --service_id $NOVA_SERVICE_ID --publicurl $PUBLIC --adminurl $ADMIN --internalurl $INTERNAL

# OpenStack Compute EC2 API
EC2_SERVICE_ID=$(keystone service-list | awk '/\ ec2\ / {print $2}')

PUBLIC="http://$ENDPOINT:8773/services/Cloud"
ADMIN="http://$ENDPOINT:8773/services/Admin"
INTERNAL=$PUBLIC

keystone endpoint-create --region RegionOne --service_id $EC2_SERVICE_ID --publicurl $PUBLIC --adminurl $ADMIN --internalurl $INTERNAL

# Cinder Block Storage Service
CINDER_SERVICE_ID=$(keystone service-list | awk '/\ volume\ / {print $2}')
CINDER_ENDPOINT=$(echo $OSCONTROLLER | sed 's/\.[0-9]*$/.211/') #Change last octet of OpenStack Controller IP to the Cinder IP.  Concerned about hardcoding it...
PUBLIC="http://$CINDER_ENDPOINT:8776/v1/%(tenant_id)s" 
ADMIN=$PUBLIC
INTERNAL=$PUBLIC

keystone endpoint-create --region RegionOne --service_id $CINDER_SERVICE_ID --publicurl $PUBLIC --adminurl $ADMIN --internalurl $INTERNAL


# Service Tenant
keystone tenant-create --name service --description "Service Tenant" --enabled true

SERVICE_TENANT_ID=$(keystone tenant-list | awk '/\ service\ / {print $2}')
keystone user-create --name keystone --pass keystone --tenant_id $SERVICE_TENANT_ID --email keystone@localhost --enabled true

keystone user-create --name glance --pass glance --tenant_id $SERVICE_TENANT_ID --email glance@localhost --enabled true

keystone user-create --name nova --pass nova --tenant_id $SERVICE_TENANT_ID --email nova@localhost --enabled true

keystone user-create --name cinder --pass cinder --tenant_id $SERVICE_TENANT_ID --email cinder@localhost --enabled true


# Set user ids
ADMIN_ROLE_ID=$(keystone role-list | awk '/\ admin\ / {print $2}')
KEYSTONE_USER_ID=$(keystone user-list | awk '/\ keystone\ / {print $2}')
GLANCE_USER_ID=$(keystone user-list | awk '/\ glance\ / {print $2}')
NOVA_USER_ID=$(keystone user-list | awk '/\ nova\ / {print $2}')
CINDER_USER_ID=$(keystone user-list | awk '/\ cinder \ / {print $2}')

# Assign the keystone user the admin role in service tenant
keystone user-role-add --user $KEYSTONE_USER_ID --role $ADMIN_ROLE_ID --tenant_id $SERVICE_TENANT_ID

# Assign the glance user the admin role in service tenant
keystone user-role-add --user $GLANCE_USER_ID --role $ADMIN_ROLE_ID --tenant_id $SERVICE_TENANT_ID

# Assign the nova user the admin role in service tenant
keystone user-role-add --user $NOVA_USER_ID --role $ADMIN_ROLE_ID --tenant_id $SERVICE_TENANT_ID

# Assign the cinder user the admin role in service tenant
keystone user-role-add --user $CINDER_USER_ID --role $ADMIN_ROLE_ID --tenant_id $SERVICE_TENANT_ID

###############################
# Glance Install
###############################

# Install Service
sudo apt-get update
sudo apt-get -y --force-yes install glance
#sudo apt-get -y --force-yes install glance-client # borks because of repo issues. I presume will be fixed.
sudo apt-get -y --force-yes install python-glanceclient 

###############################
# Glance Configure
###############################

# Create database
MYSQL_ROOT_PASS=openstack
MYSQL_GLANCE_PASS=openstack
mysql -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE glance;'
mysql -uroot -p$MYSQL_ROOT_PASS -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%';"
mysql -uroot -p$MYSQL_ROOT_PASS -e "SET PASSWORD FOR 'glance'@'%' = PASSWORD('$MYSQL_GLANCE_PASS');"

# glance-api-paste.ini
echo "service_protocol = http
service_host = ${MY_IP}
service_port = 5000
auth_host = ${MY_IP}
auth_port = 35357
auth_protocol = http
auth_uri = http://${MY_IP}:5000/
admin_tenant_name = service
admin_user = glance
admin_password = glance
" | sudo tee -a /etc/glance/glance-api-paste.ini

# glance-api.conf
echo "config_file = /etc/glance/glance-api-paste.ini
flavor = keystone
" | sudo tee -a /etc/glance/glance-api.conf

# glance-registry-paste.ini
echo "service_protocol = http
service_host = ${MY_IP}
service_port = 5000
auth_host = ${MY_IP}
auth_port = 35357
auth_protocol = http
auth_uri = http://${MY_IP}:5000/
admin_tenant_name = service
admin_user = glance
admin_password = glance
" | sudo tee -a /etc/glance/glance-registry-paste.ini

# glance-registry.conf
echo "config_file = /etc/glance/glance-registry-paste.ini
flavor = keystone
" | sudo tee -a /etc/glance/glance-registry.conf

sudo sed -i "s,^sql_connection.*,sql_connection = mysql://glance:${MYSQL_GLANCE_PASS}@${MYSQL_HOST}/glance," /etc/glance/glance-registry.conf
sudo sed -i "s,^sql_connection.*,sql_connection = mysql://glance:${MYSQL_GLANCE_PASS}@${MYSQL_HOST}/glance," /etc/glance/glance-api.conf

sudo stop glance-registry
sudo start glance-registry
sudo stop glance-api
sudo start glance-api

sudo glance-manage db_sync

# Get some images and upload
export OS_TENANT_NAME=cookbook
export OS_USERNAME=admin
export OS_PASSWORD=openstack
export OS_AUTH_URL=http://${MY_IP}:5000/v2.0/
export OS_NO_CACHE=1

sudo apt-get -y install wget

# Get the images
# First check host
CIRROS="cirros-0.3.0-x86_64-disk.img"
UBUNTU="precise-server-cloudimg-amd64-disk1.img"

if [[ ! -f /vagrant/${CIRROS} ]]
then
        # Download then store on local host for next time
	wget --quiet https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img 
else
	cp /vagrant/${CIRROS} .
fi

if [[ ! -f /vagrant/${UBUNTU} ]]
then
        # Download then store on local host for next time
	wget --quiet http://uec-images.ubuntu.com/precise/current/precise-server-cloudimg-amd64-disk1.img       
else
	cp /vagrant/${UBUNTU} .
fi

glance image-create --name='Ubuntu 12.04 x86_64 Server' --disk-format=qcow2 --container-format=bare --public < precise-server-cloudimg-amd64-disk1.img
glance image-create --name='Cirros 0.3' --disk-format=qcow2 --container-format=bare --public < cirros-0.3.0-x86_64-disk.img

###############################
# Nova Install
###############################

# Create database
MYSQL_HOST=${MY_IP}
GLANCE_HOST=${MY_IP}
KEYSTONE_ENDPOINT=${MY_IP}
SERVICE_TENANT=service
SERVICE_PASS=nova

MYSQL_ROOT_PASS=openstack
MYSQL_NOVA_PASS=openstack
mysql -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE nova;'
mysql -uroot -p$MYSQL_ROOT_PASS -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%'"
mysql -uroot -p$MYSQL_ROOT_PASS -e "SET PASSWORD FOR 'nova'@'%' = PASSWORD('$MYSQL_NOVA_PASS');"

sudo apt-get -y --force-yes install rabbitmq-server nova-api nova-scheduler nova-objectstore dnsmasq nova-conductor

# Clobber the nova.conf file with the following
NOVA_CONF=/etc/nova/nova.conf
NOVA_API_PASTE=/etc/nova/api-paste.ini

cat > /tmp/nova.conf << EOF
[DEFAULT]
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf
verbose=True

api_paste_config=/etc/nova/api-paste.ini
enabled_apis=ec2,osapi_compute,metadata

# Libvirt and Virtualization
libvirt_use_virtio_for_bridges=True
connection_type=libvirt
libvirt_type=qemu

# Database
sql_connection=mysql://nova:openstack@${MYSQL_HOST}/nova

# Messaging
rabbit_host=${MYSQL_HOST}

# EC2 API Flags
ec2_host=${MYSQL_HOST}
ec2_dmz_host=${MYSQL_HOST}
ec2_private_dns_show_ip=True

# Network settings
public_interface=eth1
force_dhcp_release=True
auto_assign_floating_ip=True
#Metadata
#metadata_host = ${MYSQL_HOST}
#metadata_listen = ${MYSQL_HOST}
#metadata_listen_port = 8775

# Cinder #
volume_driver=nova.volume.driver.ISCSIDriver
enabled_apis=ec2,osapi_compute,metadata
volume_api_class=nova.volume.cinder.API
iscsi_helper=tgtadm
 #set private IP address for providing iSCSI storage to VMs
iscsi_ip_address = $(echo $OSCONTROLLER_P | sed 's/\.[0-9]*$/.211/')
 #may not be necessary
volume_name_template = volume-%s
 #LVM Group name generated by cinder.sh
volume_group = cinder-volumes


# Images
image_service=nova.image.glance.GlanceImageService
glance_api_servers=${GLANCE_HOST}:9292

# Scheduler
scheduler_default_filters=AllHostsFilter

# Object Storage <--- ??? Placeholder for Swift?
#iscsi_helper=tgtadm

# Auth
auth_strategy=keystone
keystone_ec2_url=http://${KEYSTONE_ENDPOINT}:5000/v2.0/ec2tokens

EOF

sudo rm -f $NOVA_CONF
sudo mv /tmp/nova.conf $NOVA_CONF
sudo chmod 0640 $NOVA_CONF
sudo chown nova:nova $NOVA_CONF

# Paste file
sudo sed -i "s/127.0.0.1/$KEYSTONE_ENDPOINT/g" $NOVA_API_PASTE
sudo sed -i "s/%SERVICE_TENANT_NAME%/$SERVICE_TENANT/g" $NOVA_API_PASTE
sudo sed -i "s/%SERVICE_USER%/nova/g" $NOVA_API_PASTE
sudo sed -i "s/%SERVICE_PASSWORD%/$SERVICE_PASS/g" $NOVA_API_PASTE

sudo nova-manage db sync

sudo stop nova-api
sudo stop nova-scheduler
sudo stop nova-objectstore
sudo stop nova-conductor

sudo start nova-api
sudo start nova-scheduler
sudo start nova-objectstore
sudo start nova-conductor

###############################
# Cinder DB Create
###############################

# Install the DB
MYSQL_ROOT_PASS=openstack
MYSQL_CINDER_PASS=openstack
mysql -uroot -p$MYSQL_ROOT_PASS -e 'CREATE DATABASE cinder;'
mysql -uroot -p$MYSQL_ROOT_PASS -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%';"
mysql -uroot -p$MYSQL_ROOT_PASS -e "SET PASSWORD FOR 'cinder'@'%' = PASSWORD('$MYSQL_CINDER_PASS');"

###############################
# OpenStack Deployment Complete
###############################

# Create a .stackrc file
cat > /vagrant/.stackrc <<EOF
export OS_TENANT_NAME=cookbook
export OS_USERNAME=admin
export OS_PASSWORD=openstack
export OS_AUTH_URL=http://${MY_IP}:5000/v2.0/
EOF

#Pass Controller IP to Common.sh and other nodes
cat > /vagrant/.controller <<EOF
export CONTROLLER_HOST=${MY_IP}
export CONTROLLER_HOST_PRIV=${MY_PRIV_IP}
EOF

