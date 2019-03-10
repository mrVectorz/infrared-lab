infrared virsh lab installation
===============================

On your workstation, install the required dependencies :

```shell
sudo dnf install git gcc libffi-devel openssl-devel python-virtualenv libselinux-python redhat-rpm-config -y
```

Prepare a virtual environment for infrared :

```shell
  virtualenv ~/.venv_infrared
  source ~/.venv_infrared/bin/activate
  pip install --upgrade pip
  pip install --upgrade setuptools
```

Installing infrared :

```shell
  cd ~/.venv_infrared
  git clone https://github.com/redhat-openstack/infrared.git
  cd infrared
  pip install .
  echo ". $(pwd)/etc/bash_completion.d/infrared" >> ${VIRTUAL_ENV}/bin/activate
```

## SSH key for the lab

infrared use ssh for the deployment and needs an ssh key.

NOTE : You can use your already existing ssh key but be sure to replace the relevant argument when running infrared commands.

To generate a ssh key on your wks:

```shell
ssh-keygen -f ~/.ssh/key_sbr_lab
```

Copy the key to your lab server :

```shell
ssh-copy-id -i ~/.ssh/key_sbr_lab.pub root@$YOURLABSERVER
```

## OSP 13 hybrid deployment

Create a workspace (if it does not exist yet) :

```shell
infrared workspace create $YOURLABSERVER
```

Cleanup the system :

```shell
infrared virsh --host-address $YOURLABSERVER --host-key ~/.ssh/key_sbr_lab --cleanup true
```

Setup networking :

!! Need to configure bridges on the host first

```shell
cat << EOF > plugins/virsh/vars/topology/network/3_bridges_1_net.yml
# br-ctlplane - provisioning
# br-vlan - OSP internal services (internal/external/tenant)
# br-link - dataplane networks
networks:
    net1:
        name: br-ctlplane
        forward: bridge
        nic: enp22s0f4
        ip_address: 10.10.179.86
        netmask: 255.255.248.0
    net2:
        name: br-vlan
        forward: bridge
        nic: enp22s0f1
    net3:
        name: br-link
        forward: bridge
        nic: enp22s0f2
    net4:
        external_connectivity: yes
        name: "management"
        ip_address: "172.16.0.1"
        netmask: "255.255.255.0"
        forward: nat
        dhcp:
            range:
                start: "172.16.0.2"
                end: "172.16.0.100"
            subnet_cidr: "172.16.0.0/24"
            subnet_gateway: "172.16.0.1"
        floating_ip:
            start: "172.16.0.101"
            end: "172.16.0.150"
nodes:
    undercloud:
        interfaces:
            - network: "br-ctlplane"
              bridged: yes
            - network: "management"
        external_network:
            network: "management"
    controller:
        interfaces:
            - network: "br-ctlplane"
              bridged: yes
            - network: "br-vlan"
              bridged: yes
            - network: "br-link"
              bridged: yes
            - network: "management"
        external_network:
            network: "management"
EOF
```

Provision the virtual nodes for the environment :

```shell
infrared virsh -v \
    --host-address $YOURLABSERVER \
    --host-key ~/.ssh/key_sbr_lab \
    --topology-network 3_bridges_1_net \
    --topology-nodes undercloud:1,controller:1 \
    -e override.undercloud.cpu=8 \
    -e override.controller.cpu=8 \
    -e override.undercloud.memory=28672 \
    -e override.controller.memory=28672 \
    -e override.undercloud.disks.disk1.size=150G \
    --image-url url_to_download_/7.5/.../rhel-guest-image....x86_64.qcow2
```

Install the undercloud :

```shell
infrared tripleo-undercloud -v \
    --version=10 \
    --build=passed_phase1 \
    --images-task=rpm \
    --config-file undercloud_hybrid.conf
```

Launch a partial deployment, it will only register, introspect and tag nodes :

```shell
infrared tripleo-overcloud --deployment-files virt --version 13 --introspect yes --tag yes --deploy no --post no
```

Alternatively, deploy the OC aswell:

```shell
infrared tripleo-overcloud --deployment-files virt --version 13 --introspect yes --tag yes --deploy yes --post yes --containers yes
```
