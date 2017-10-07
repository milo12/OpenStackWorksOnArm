# General setup - applies to Controller and Compute

# sanity check - make sure we can reach the controller
ping controller -c 5 -q
if [ $? -ne 0 ] ; then
  echo "controller is unreachable"
  echo "check /etc/hosts and networking and then restart this script"
  read -p "press a key"
  exit -1
fi

# private IP addr (10...)
MY_IP=`hostname -I | xargs -n1 | grep "^10\." | head -1`


# general system updates
apt-get -y update

# non-interactively set a timezone so we're not interactively prompted
export DEBIAN_FRONTEND=noninteractive
apt-get install -y tzdata
ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata

# OpenStack needs precise time services
apt-get -y install chrony
service chrony restart

apt-get -y install software-properties-common
add-apt-repository -y cloud-archive:pike
apt-get -y update
apt-get -y install python-openstackclient


# easy modification of .ini configuration files
apt-get -y install crudini


## rabbitmq
apt-get -y install rabbitmq-server
rabbitmqctl add_user openstack RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
## end of rabbitmq

## memcached
apt-get -y install memcached python-memcache
# set the IP where memchaced is listening
sed -i '/^-l.*/c\-l '$MY_IP /etc/memcached.conf
service memcached restart
## end of memcached

## etcd
groupadd --system etcd
useradd --home-dir "/var/lib/etcd" \
      --system \
      --shell /bin/false \
      -g etcd \
      etcd
      
mkdir -p /etc/etcd
chown etcd:etcd /etc/etcd
mkdir -p /var/lib/etcd
chown etcd:etcd /var/lib/etcd

ETCD_VER=v3.2.7
rm -rf /tmp/etcd && mkdir -p /tmp/etcd
ARCH=`dpkg --print-architecture`
curl -L https://github.com/coreos/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-${ARCH}.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-${ARCH}.tar.gz
tar xzvf /tmp/etcd-${ETCD_VER}-linux-${ARCH}.tar.gz -C /tmp/etcd --strip-components=1
cp /tmp/etcd/etcd /usr/bin/etcd
cp /tmp/etcd/etcdctl /usr/bin/etcdctl

cat > /etc/etcd/etcd.conf.yml << EOF
name: controller
data-dir: /var/lib/etcd
initial-cluster-state: 'new'
initial-cluster-token: 'etcd-cluster-01'
initial-cluster: controller=http://${MY_IP}:2380
initial-advertise-peer-urls: http://${MY_IP}:2380
advertise-client-urls: http://${MY_IP}:2379
listen-peer-urls: http://0.0.0.0:2380
listen-client-urls: http://${MY_IP}:2379
EOF
      
cat > /lib/systemd/system/etcd.service << EOF
[Unit]
After=network.target
Description=etcd - highly-available key value store

[Service]
Environment="ETCD_UNSUPPORTED_ARCH=arm64"
LimitNOFILE=65536
Restart=on-failure
Type=notify
ExecStart=/usr/bin/etcd --config-file /etc/etcd/etcd.conf.yml
User=etcd

[Install]
WantedBy=multi-user.target
EOF

systemctl enable etcd
systemctl start etcd
## end of etcd