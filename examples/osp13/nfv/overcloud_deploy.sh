#!/bin/bash
template_base_dir=/home/stack/osp13-dpdk

if ! [ -f ${template_base_dir}/overcloud_images.yaml ]; then
  openstack overcloud container image prepare \
    --namespace=registry.access.redhat.com/rhosp13 \
    --prefix=openstack- \
    -e /usr/share/openstack-tripleo-heat-templates/environments/services-docker/neutron-ovs-dpdk.yaml \
    --set ceph_namespace=registry.access.redhat.com/rhceph \
    --set ceph_image=rhceph-3-rhel7 \
    --tag-from-label {version}-{release} \
    --output-env-file=${template_base_dir}/overcloud_images.yaml
fi

openstack overcloud deploy --templates \
-r ${template_base_dir}/roles_data.yaml \
-e ${template_base_dir}/overcloud_images.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/host-config-and-reboot.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/services-docker/neutron-ovs-dpdk.yaml \
-e /usr/share/openstack-tripleo-heat-templates/environments/ovs-dpdk-permissions.yaml \
-e ${template_base_dir}/network-environment.yaml \
-e ${template_base_dir}/node-count.yaml \
-e ${template_base_dir}/dpdk-conf.yaml \
--log-file /home/stack/overcloud_install.log

