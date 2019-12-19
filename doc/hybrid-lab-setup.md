# infrared virsh hybrid lab installation
---

Deploying an Openstack Tripleo environment on a mix of physical and virtual servers.

###  Index
1. [Setup](#Setup)
   1. [Dependencies](#Dependencies)
   2. [SSH Authentication](#SSH-key)
   3. [Ease of use](#Ease-of-use)
   4. [infrared workspace](#Creating-the-infrared-workspace)
2. [Deployment](#Deployment)
    1. [Deploying the virtual layer](#Deploying-the-virtual-layer)
    2. [Deploying the Undecloud](#Deploying-the-Undecloud)
    3. [Tagging and introspection](#Tagging-and-introspection)
    4. [Deploying the Overcloud](#Deploying-the-Overcloud)
3. [Post Deployment](#Post-Deployment)
    1. [Creating an Ansible inventory](#Creating-an-ansible-inventory)
    2. [Quick deployment tests](#Quick-deployment-tests)
4. [Cleanup](#Cleanup)

## Setup

The setup required to start doing the UC and OC deployment.

### Dependencies
On your workstation where you will run infrared commands, install the following dependencies :

```shell
  sudo dnf install -y git gcc libffi-devel openssl-devel python-virtualenv libselinux-python redhat-rpm-config
```

Prepare a python virtual environment for infrared :

```shell
  git clone https://github.com/redhat-openstack/infrared.git
  cd infrared
  virtualenv .venv
  source .venv/bin/activate
  pip install --upgrade pip
  pip install --upgrade setuptools
  pip install .
  echo ". $(pwd)/etc/bash_completion.d/infrared" >> ${VIRTUAL_ENV}/bin/activate
  infrared plugin list
```

### SSH key

infrared uses `ssh` for the deployment and thus needs an ssh key.

NOTE : You can use your already existing ssh key but be sure to replace the relevant argument when running infrared commands.

To generate a ssh key on your wks:

```shell
  ssh-keygen -f ~/.ssh/key_sbr_lab
```

Copy the key to your lab server and set the variable `private_key` to be the full path of the key used in the deployment:

```shell
  ssh-copy-id -i ~/.ssh/key_sbr_lab.pub root@$YOURLABSERVER
```

### Ease of use

We will be using in this example some variables to avoid having to retype them all the time.
- `YOURLABSERVER` will be used to designate the host (IP or hostname) of the desired host of the virtualized environment.
- `private_key` will be mapped to the full path of the private key deployed on the host.

Example of setting the above mentionned system variables:
```shell
  YOURLABSERVER=my-poc.example.com
  private_key=~/.ssh/key_sbr_lab
```

Then checkout this workspace :
```shell
infrared workspace checkout $YOURLABSERVER
```

Cleanup the system :
=======
### Creating the infrared workspace

Create a workspace (if it does not exist yet), then checkout to make use of it :

```shell
  infrared workspace create $YOURLABSERVER
  infrared workspace checkout $YOURLABSERVER
```

## Deployment

The deployment is split between:
- configuring the virtual networking
- deploying the virtual guests (example is deploying controllers nodes and a director node)
- tagging and introspection of all overcloud nodes
- deploying overcloud

### Deploying the virtual layer

Provision the virtual nodes for the environment :

```shell
  infrared virsh -v \
    --host-address $YOURLABSERVER \
    --host-key ${private_key} \
    --host-mtu-size=9000 \
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
    --image-url https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-1907.qcow2
```

Note: If you have a valid Red Hat subscription get your download link and replace the centos url.

### Deploying the Undecloud

Install the undercloud :

```shell
  infrared tripleo-undercloud -v \
    --version=13 \
    --build=passed_phase2 \
    --images-task=rpm \
    --ssl no
```

### Tagging and introspection

Launch a partial deployment; it will only register, introspect and tag the overcloud nodes.
In the bellow example we use custom deployment templates that match our network needs.

```shell
  infrared tripleo-overcloud -vv -o prepare_instack.yml \
    --version 13 \
    --deployment-files /root/gss-stack-tools/deployments/rdu2/lab2/templates/osp13/dpdk/ \
    --introspect=yes \
    --tagging=yes \
    --deploy=no \
    -e provison_virsh_network_name=br-ctlplane \
    --hybrid /root/gss-stack-tools/deployments/rdu2/lab2/instackenv.json
```

The instackenv.json file contains the information of the physical nodes for hybrid deployment.
Example json file:

```
{
  "nodes": [
    {
      "mac": [
        "18:66:da:9f:b0:c5"
      ],
      "cpu": "64",
      "name": "compute-01",
      "memory": "8008712",
      "disk": "40",
      "arch": "x86_64",
      "pm_type": "pxe_ipmitool",
      "pm_user": "ipmi_user",
      "pm_password": "ipmi_password",
      "pm_addr": "10.10.10.10"
    }
  ]
}
```

### Deploying the Overcloud

This command deploys the overcloud with a specific overcloud deply script.
We do not need to tag and introspect again as it was done in the previous step.

```shell
  infrared tripleo-overcloud -vv \
    --version 13 \
    --deployment-files /root/gss-stack-tools/deployments/rdu2/lab2/templates/osp13/dpdk/ \
    --introspect=no \
    --tagging=no \
    --deploy=yes \
    --overcloud-script /root/gss-stack-tools/deployments/rdu2/lab2/templates/osp13/dpdk/overcloud_deploy.sh
```

## Post Deployment

You've now deployed an overcloud and undercloud, you can start using this environment as desired.
Bellow are some examples of what can be done.

### Creating an ansible inventory

If you desire to use ansible from the same deployment host, you will require an inventory file.
To generate it with infrared:

```shell
  infrared tripleo-inventory \
    -o tripleo-inventory.yml \
    --host $host \
    --user root \
    --ssh-key ${private_key} \
    --setup-type virt \
    --custom-undercloud-user stack \
    --overcloud-user "heat-admin" \
    --undercloud-groups "undercloud,tester" \
    --hypervisor-groups "hypervisor,shade" \
    --undercloud-only false
```

### Quick deployment tests

Copy the script in the `tools` directory within this git repository.
```shell
  scp root@${infrared-lab-dir}/tools/overcloud-test.sh ./
```

Then run the `overcloud-test.sh` it will do the following on the overcloud:
- create a few networks
- create respective subnets
- create routers
- add router ports to the router
- download cirros guest image
- download centos guest image
- create images and flavors
- create security groups
- create instances
- boot a couple instances

```shell
  bash overcloud-test.sh
```

## Cleanup

Cleaning up the lab is accomplished with infrared also, thus make sure to checkout the correct workspace.

```shell
  infrared workspace checkout $YOURLABSERVER
  infrared virsh --host-address $YOURLABSERVER --host-key ${private_key} --cleanup true
```

Depending on how this was setup and how much cleaning needs to be done, you may need to manually delete the bridges.
First `ssh` to the virt lab server.

```shell
 ssh root@$YOURLABSERVER
```

Next we delete the bridges on that node.

```shell
  brctl delbr br-data
  brctl delbr br-ctlplane
  brctl delbr br-link
  brctl delbr br-vlan
```
