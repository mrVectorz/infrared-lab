## infrared installation

On your workstation, install the required dependencies :

```shell
sudo dnf install git gcc libffi-devel openssl-devel python-virtualenv libselinux-python redhat-rpm-config -y
```
Installing infrared :

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

infrared uses ssh for the deployment and needs an ssh key.

NOTE : You can use your already existing ssh key, but be sure to replace the relevant argument when running infrared commands.

To generate a ssh key on your wks:

```shell
ssh-keygen -f ~/.ssh/key_sbr_lab
```

Copy the key to your lab server :

```shell
ssh-copy-id -i ~/.ssh/key_sbr_lab.pub root@$YOURLABSERVER
```

## OSP 13 deployment

As the latest long support offering of Red Hat is RHOSP 13, we shall use it as the prime example.

1. Create a new workspace
Infrared works with what it calls workspaces. Consider these environments, you can have multiple environments at once and switch between them.

To create your workspace (if it does not exist yet) :

```shell
infrared workspace create $YOURLABSERVER
```

2. Cleaning up the workspace
Cleanup the system to assure that nothing remains from an old deployment :

```shell
infrared virsh --host-address $YOURLABSERVER --host-key ~/.ssh/key_sbr_lab --cleanup yes
```

3. We need to setup the guest vms and network
We prepare the environment selecting what image to use, the cloud's topology and any further overrides.

```shell
infrared virsh --host-address $YOURLABSERVER \
  --host-key ~/.ssh/key_sbr_lab \
  --topology-nodes undercloud:1,controller:3,compute:1 \
  -e override.controller.cpu=8 \
  -e override.controller.memory=12288 \
  -e override.undercloud.disks.disk1.size=200G \
  --image-url url_to_download_/7.6/.../rhel-guest-image....x86_64.qcow2
```

4. Install the undercloud

You have to set the container registry namespace to the version required, as default has now changed to rhosp14
```shell
infrared tripleo-undercloud --version 13 \
  --registry-namespace rhosp13 \
  --images-task=rpm \
  --cdn ./examples/rh-subscription.yaml \
  --ssl no \
  --build ga
```

If you want to use custom repositories (but cannot overlap with ones already managed by rhn if already subscribed), you will then use the `--repos-config` parameter. An example of such a template is included here: "./examples/rh-registry.yaml"
IR uses the yum_repository module, for more information see the [upstream documentation](https://docs.ansible.com/ansible/latest/modules/yum_repository_module.html). Do note that IR does not make use of all parameters for some reason.

Backup the UC node :
```shell
infrared tripleo-undercloud --snapshot-backup yes
```

If we want to update and such the overcloud nodes, we will want them to be registered with the subscription manager. To do that we will add the following parameters (and template) for the IR command:
```shell
  --config-heat rhel_reg_activation_key=EXAMPLE_KEY \
  --config-heat rhel_reg_org=EXAMPLE_ORG \
  --overcloud-templates ./examples/oc_register.yaml
```

We start the overcloud deployment process with registering, introspecting and tagging the nodes :

```shell
infrared tripleo-overcloud \
  --deployment-files virt \
  --version 13 \
  --config-heat rhel_reg_activation_key=EXAMPLE_KEY \
  --config-heat rhel_reg_org=EXAMPLE_ORG \
  --overcloud-templates ./examples/oc-register.yaml \
  --registry-mirror registry.access.redhat.com/rhosp13 \
  --registry-tag latest \
  --registry-prefix=openstack- \
  --introspect yes \
  --tagging yes \
  --registry-skip-puddle yes \
  --deploy no
```

5. Deploying the overcloud
Here we deploy the overcloud will all intended templates.

```shell
infrared tripleo-overcloud \
  --deployment-files virt \
  --version 13 \
  --config-heat rhel_reg_activation_key=EXAMPLE_KEY \
  --config-heat rhel_reg_org=EXAMPLE_ORG \
  --overcloud-templates ./examples/oc-register.yaml \
  --registry-mirror registry.access.redhat.com/rhosp13 \
  --registry-tag latest \
  --registry-prefix=openstack- \
  --introspect no \
  --tagging no \
  --deploy yes \
  --registry-skip-puddle yes \
  --containers yes
```

Once done you can use the cloud-config plugin post creation to create networks and stuff (broken at times):

```shell
infrared cloud-config -vv \ 
-o cloud-config.yml \ 
--deployment-files virt \ 
--tasks create_external_network,forward_overcloud_dashboard,network_time,tempest_deployer_input
```

## Additional Recommendations

- Lowering the UC node's memory footprint
Once the UC node deployed, depending on the size of you lab server (typical is 64Gb), it could be useful to lower the worker counts to 1 to limit memory usage. You can use [this script](https://github.com/mrVectorz/snips/blob/master/osp/low_memory_uc.sh) to do it. (Need to fix it for OSP14.

- Lowering the memory usage on the controllers
Just as before, in a lab/PoC environment, operators do not need all the workers configured.
To lower the counts on the controller nodes simply include the tripleo environment template:
`/usr/share/openstack-tripleo-heat-templates/environments/low-memory-usage.yaml`

To do this in your OC deployment via IR create a template locally:
example: infra_low_mem.yaml
```shell
tripleo_heat_templates:
    - /usr/share/openstack-tripleo-heat-templates/environments/low-memory-usage.yaml
```

Once saved simply include it in your tripleo-overcloud command. Example:
```shell
infrared tripleo-overcloud --deployment-files virt --version 13 --introspect yes --tagging yes --deploy yes --containers yes --overcloud-templates infra_low_mem.yaml
```
This will add it to the OC deployment command as an environment file.

