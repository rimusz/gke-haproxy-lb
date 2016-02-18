# Internal LoadBalancer for GKE clusters

#### It is based on [GC Internal LB](https://cloud.google.com/solutions/internal-load-balancing-haproxy)

Internal LoadBalancer script allows to bootstrap HAProxy based VM, which watches 
GKE Nodes each two minutes and updates HAProxy config file if node/s IP got changed and then restarts the HAProxy.

How to use it:
---

- Run the command below:

```
$ git clone https://github.com/rimusz/gke-internal-lb
```
- Update script's `create_internal_lb.sh` the part shown below with your GC project and zone (and other settings if you want to):

```
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
##############################################################################
```
- Then run:

```
$ ./create_internal_lb.sh
```

What `create_internal_lb.sh` does:
---

- Check for existing setup and deletes it all dependencies
- Creates a temporal VM, set's it up
- Deletes the temporal VM keeping it's boot disk
- Creates the custom image from the boot disk
- Creates HAProxy instance template based on the custom image
- Creates a managed instance group with the 1 VM which has a static IP

So what do you get then:
---
- Internal Loadbalancer VM forwards received `http` trafic to all GKE cluster Nodes port 80 (the port can be changed in `get_vms_ip.tmpl`)
- The Internal LoadBalance VM is watched by the Instance Group Manager, if the VM stops it gets restarted then
- VM's HAProxy service is set to always restart, systemd restarts the service if it stops.
- Script `/opt/bin/get_vms_ip` gets run by `cron` every two minutes (it can be changed), checks for GKE Nodes IP changes, updates HAProxy config file if node/s IP got changed and then restarts HAProxy.


