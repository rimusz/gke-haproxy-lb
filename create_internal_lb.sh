#!/bin/bash

##############################################################################
# GC settings
# your project
PROJECT=_YOUR_PROJECT_
# your GKE cluster zone or which ever zone you want to put the internal LB VM
ZONE=_YOUR_ZONE_
#

# GKE cluster VM name without all those e.g -364478-node-sa5c
SERVERS=gke-cluster-1

# static IP for the internal LB VM
STATIC_IP=10.200.252.10

# VM type
MACHINE_TYPE=g1-small

# set VMs name
BASE_VM_NAME=$SERVERS-lb-base
VM_NAME=$SERVERS-int-lb
##############################################################################

#
gcloud config set project $PROJECT
gcloud config set compute/zone $ZONE

### base VM
# create an instance which disk will be used as a base image later one
gcloud compute instances create $BASE_VM_NAME --image debian-8 \
 --scopes compute-rw --machine-type=$MACHINE_TYPE --can-ip-forward

sleep 10

# install haproxy 
gcloud compute ssh $BASE_VM_NAME --command "sudo apt-get update && sudo apt-get -y install haproxy"

# make a folder /opt/haproxy to store the config file
gcloud compute ssh $BASE_VM_NAME --command "sudo mkdir -p /opt/haproxy  && sudo cp -f /etc/haproxy/haproxy.cfg /opt/haproxy/haproxy.cfg.template"

# update haproxy.cfg.template file
gcloud compute ssh $BASE_VM_NAME --command \
'echo -e "\n\n# Listen for incoming traffic
listen http-lb *:80
    mode http
    balance roundrobin
    option httpclose
    option forwardfor" | sudo tee -a /opt/haproxy/haproxy.cfg.template'

# update and copy 'get_vms_ip' script to the VM
cp -f get_vms_ip.tmpl get_vms_ip
sed -i "" 's/_PROJECT_/'$PROJECT'/' get_vms_ip
sed -i "" 's/_SERVERS_/'$SERVERS'/' get_vms_ip
gcloud compute copy-files get_vms_ip $BASE_VM_NAME:/tmp
gcloud compute ssh $BASE_VM_NAME --command "sudo mkdir -p /opt/bin && sudo cp /tmp/get_vms_ip /opt/bin && sudo chmod +x /opt/bin/get_vms_ip"

# enable cron job to run each 2 minutes
gcloud compute ssh $BASE_VM_NAME --command 'echo "*/2 * * * * /opt/bin/get_vms_ip" | sudo tee /var/spool/cron/crontabs/root && sudo chmod 600 /var/spool/cron/crontabs/root'

# add network eth0:0 with the static IP
gcloud compute ssh $BASE_VM_NAME --command \
'echo -e "# static IP
auto eth0:0
iface eth0:0 inet static
  address '$STATIC_IP'
  netmask 255.255.255.0" | sudo tee -a /etc/network/interfaces'
gcloud compute ssh $BASE_VM_NAME --command "sudo ifup eth0:0"
###

sleep 5

### Create the custom image
# Terminate the instance but keep the boot disk
gcloud compute instances stop $BASE_VM_NAME
gcloud compute instances delete $BASE_VM_NAME --keep-disks boot
# Create the custom image using the source disk that you just created
gcloud compute images create $BASE_VM_NAME-image --source-disk $BASE_VM_NAME
#

# Create an HAProxy instance template based on the custom image
gcloud compute instance-templates create $VM_NAME-template --image $BASE_VM_NAME-image \
 --scopes compute-rw --machine-type=$MACHINE_TYPE --can-ip-forward

# Create a managed instance group named $VM_NAME
gcloud compute instance-groups managed create $VM_NAME \
 --base-instance-name $VM_NAME --size 1 --template $VM_NAME-template

sleep 25

### Set static IP route

# Get VM's full name
VM_FULL_NAME=$(gcloud compute instances list | grep -v grep | grep $VM_NAME | awk {'print $1'})

# Delete the old one route if such exists
OLD_ROUTE=$(gcloud compute routes list | grep $STATIC_IP | awk {'print $1'})
gcloud compute routes delete $OLD_ROUTE

# Create the route for VM's static IP
gcloud compute routes create ip-$VM_FULL_NAME \
         --next-hop-instance $VM_FULL_NAME \
            --next-hop-instance-zone $ZONE \
                --destination-range $STATIC_IP/32
