#!/bin/bash

PROVIDER_SEGMENTATION_ID_PRIVATE=106
PROVIDER_SEGMENTATION_ID_PRIVATE2=107
PROVIDER_SEGMENTATION_ID_MGMT=108
PROVIDER_PHYSICAL_NETWORK="tenant"
PROVIDER_PHYSICAL_NETWORK_EXTERNAL="external"
CIRROS_INSTANCE_COUNT=1
RHEL_INSTANCE_COUNT=1

source /home/stack/overcloudrc



if ! `neutron net-list | grep -q private1`;then
  neutron net-create private1 --provider:network_type vlan --provider:physical_network $PROVIDER_PHYSICAL_NETWORK --provider:segmentation_id $PROVIDER_SEGMENTATION_ID_PRIVATE --shared --router:external
fi
if ! `neutron net-list | grep -q private2`;then
  neutron net-create private2 --provider:network_type vlan --provider:physical_network $PROVIDER_PHYSICAL_NETWORK --provider:segmentation_id $PROVIDER_SEGMENTATION_ID_PRIVATE2 --shared --router:external
fi
if ! `neutron net-list | grep -q provider1`;then
  neutron net-create provider1 --provider:network_type flat --provider:physical_network $PROVIDER_PHYSICAL_NETWORK_EXTERNAL --shared --router:external
fi
if ! `neutron net-list | grep -q private-mgmt`;then
  neutron net-create private-mgmt --provider:network_type vlan --provider:physical_network $PROVIDER_PHYSICAL_NETWORK --provider:segmentation_id $PROVIDER_SEGMENTATION_ID_MGMT --shared --router:external
fi

if ! `neutron subnet-list | grep -q provider1-subnet`;then
  neutron subnet-create --gateway 172.16.0.1 --allocation-pool start=172.16.0.100,end=172.16.0.150 --dns-nameserver 10.11.5.4 --name provider1-subnet provider1 172.16.0.0/24
fi
if ! `neutron subnet-list | grep -q provider1-ipv6-subnet`;then
  neutron subnet-create --ip-version 6 --ipv6-ra-mode slaac --ipv6-address-mode slaac --gateway 2000:10::250  --name provider1-ipv6-subnet provider1 2000:10::/64
fi

if ! `neutron router-list | grep -q router`;then
  neutron router-create router
  neutron router-gateway-set router provider1
fi
if ! `neutron router-list | grep -q router-ipv6`;then
  neutron router-create router-ipv6
  neutron router-gateway-set router-ipv6 provider1
fi

if ! `neutron subnet-list | grep -q private1-subnet`;then
  neutron subnet-create --name private1-subnet private1 192.168.0.0/24 --allocation-pool start=192.168.0.100,end=192.168.0.150 
  neutron router-interface-add router private1-subnet
fi
if ! `neutron subnet-list | grep -q private1-ipv6-subnet`;then
  neutron subnet-create --ip-version 6 --ipv6-ra-mode slaac --ipv6-address-mode slaac --name private1-ipv6-subnet private1 2000:192:168:0::/64
  neutron router-interface-add router-ipv6 private1-ipv6-subnet
fi

if ! `neutron subnet-list | grep -q private2-subnet`;then
  neutron subnet-create --name private2-subnet private2 192.168.1.0/24 --allocation-pool start=192.168.1.100,end=192.168.1.150 
  neutron router-interface-add router private2-subnet
fi
if ! `neutron subnet-list | grep -q private2-ipv6-subnet`;then
  neutron subnet-create --ip-version 6 --ipv6-ra-mode slaac --ipv6-address-mode slaac --name private2-ipv6-subnet private2 2000:192:168:1::/64
  neutron router-interface-add router-ipv6 private1-ipv6-subnet
fi

if ! `neutron subnet-list | grep -q private-mgmt-subnet`;then
  neutron subnet-create --name private-mgmt-subnet private-mgmt --dns-nameserver 10.11.5.4 192.168.10.0/24
  neutron router-interface-add router private-mgmt-subnet
fi
if ! `neutron subnet-list | grep -q private-mgmt-ipv6-subnet`;then
  neutron subnet-create --ip-version 6 --ipv6-ra-mode slaac --ipv6-address-mode slaac --name private-mgmt-ipv6-subnet private-mgmt 2000:192:168:10::/64
  neutron router-interface-add router-ipv6 private-mgmt-ipv6-subnet
fi

# download cirros
if ! `openstack image list | grep -q cirros`;then
  c_version=$(curl -s http://download.cirros-cloud.net/ | awk '$0 ~ /<a href="[0-9|\.]*\// {text=gensub(/.*<a href="([0-9|\.]+\/).*$/, "\\1", "g", $0)}; END {print text}')
  curl http://download.cirros-cloud.net/${c_version}cirros-${c_version::(-1)}-x86_64-disk.img -o cirros-${c_version::(-1)}-x86_64-disk.img
  openstack image create--file cirros-${c_version::(-1)}-x86_64-disk.img --container-format bare --disk-format qcow2 cirros
fi

# download centos
curl -o centos.qcow2 https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-1907.qcow2
sudo yum install libguestfs-tools -y
virt-customize -a centos.qcow2 --root-password password:Redhat01
openstack image create  --file centos.qcow2  --container-format bare --disk-format qcow2 rhel

project_id=`openstack project list | awk '/admin/ {print $2}'`
security_group_id=`openstack security group list | grep $project_id | awk '{print $2}'`
openstack security group rule create ${security_group_id} --protocol icmp                    --remote-ip 0.0.0.0/0
openstack security group rule create ${security_group_id} --protocol tcp  --dst-port 1:65535 --remote-ip 0.0.0.0/0
openstack security group rule create ${security_group_id} --protocol udp  --dst-port 1:65535 --remote-ip 0.0.0.0/0
openstack security group rule create ${security_group_id} --ethertype IPv6 --protocol icmp                    --remote-ip ::/0
openstack security group rule create ${security_group_id} --ethertype IPv6 --protocol tcp  --dst-port 1:65535 --remote-ip ::/0
openstack security group rule create ${security_group_id} --ethertype IPv6 --protocol udp  --dst-port 1:65535 --remote-ip ::/0

if ! `nova keypair-list | grep -q id_rsa`;then
  nova keypair-add --pub-key ~/.ssh/id_rsa.pub id_rsa
fi

if ! `nova flavor-list | grep -q m1.tiny`;then
  nova flavor-create m1.tiny auto 512 8 1
fi
if ! `nova flavor-list | grep -q m1.small`;then
  nova flavor-create m1.small auto 1024 16 1
fi

#openstack aggregate create --zone=dpdk dpdk
#openstack aggregate add host dpdk overcloud-compute-0.localdomain
openstack flavor set --property hw:cpu_policy=dedicated  --property hw:mem_page_size=large m1.tiny
openstack flavor set --property hw:cpu_policy=dedicated  --property hw:mem_page_size=large m1.small

PROVIDERNETID=$(openstack network show provider1 -c id -f value)
NETID=$(neutron net-list | grep private1 | awk '{print $2}')
for i in `seq 1 $CIRROS_INSTANCE_COUNT`;do 
  openstack floating ip create $PROVIDERNETID
  nova boot --nic net-id=$NETID --image cirros --flavor m1.small --key-name id_rsa cirros-test$i
  FLOATINGIP=$(openstack floating ip list --network $PROVIDERNETID  --long | grep DOWN | awk '{print $2}' | head -1)
  sleep 10
  openstack server add floating ip cirros-test$i $FLOATINGIP
done
for i in `seq 1 $RHEL_INSTANCE_COUNT`;do 
  openstack floating ip create $PROVIDERNETID
  nova boot --nic net-id=$NETID --image rhel --flavor m1.small --key-name id_rsa rhel-test$i
  FLOATINGIP=$(openstack floating ip list --network $PROVIDERNETID  --long | grep DOWN | awk '{print $2}' | head -1)
  sleep 10
  openstack server add floating ip rhel-test$i $FLOATINGIP
done

