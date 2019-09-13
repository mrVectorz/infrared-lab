infrared virsh lab installation
===============================

On your workstation, install the required dependencies :

```shell
sudo dnf install git gcc libffi-devel openssl-devel python-virtualenv libselinux-python redhat-rpm-config -y
```

Prepare a virtual environment for infrared :

```shell
  git clone https://github.com/redhat-openstack/infrared.git
  cd infrared
  virtualenv .venv
  source .venv/bin/activate
  pip install --upgrade pip
  pip install --upgrade setuptools
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

### Setup networking

Provision the virtual nodes for the environment :

```shell
infrared virsh -v \
     --host-address $YOURLABSERVER \
     --host-key ~/.ssh/gss-stack-tools \
     --topology-network 4_nets_3_bridges_hybrid \
     --topology-nodes undercloud:1,controller:3 \
     -e override.networks.net1.nic=em4 \
     -e override.networks.net2.nic=p2p1 \
     -e override.networks.net1.nic=p2p2 \
     -e override.undercloud.cpu=8 \
     -e override.controller.cpu=8 \
     -e override.undercloud.memory=28672 \
     -e override.controller.memory=28672 \
     -e override.undercloud.disks.disk1.size=150G \
     --image-url http://...rhel-guest-image-7.7-166.x86_64.qcow2
```

Install the undercloud :

```shell
infrared tripleo-undercloud -v \
    --version=13 \
    --build=passed_phase2 \
    --images-task=rpm \
    --ssl no
```

Launch a partial deployment, it will only register, introspect and tag nodes :

```shell
infrared tripleo-overcloud --deployment-files virt --version 13 --introspect yes --tag yes --deploy no --post no
```

Alternatively, deploy the OC aswell:

```shell
infrared tripleo-overcloud --deployment-files virt --version 13 --introspect yes --tag yes --deploy yes --post yes --containers yes
```
