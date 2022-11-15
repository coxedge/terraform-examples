#!/bin/bash

set -v -x -e

validatingArguments() {
  error=false
  techo debug "Validating arguments"
  if [[ -z $coxEdgeApiKey ]]; then
    techo error "Missing argument --coxedge-api-key"
    error=true
  else
    techo debug "coxEdgeApiKey: $coxEdgeApiKey"
  fi
  if [[ -z $coxEdgeOrganizationId ]]; then
    techo error "Missing argument --coxedge-organization-id"
    error=true
  else
    techo debug "coxEdgeOrganizationId: $coxEdgeOrganizationId"
  fi
  if [[ -z $coxEdgeEnvironmentName ]]; then
    techo error "Missing argument --coxedge-environment-name"
    error=true
  else
    techo debug "coxEdgeEnvironmentName: $coxEdgeEnvironmentName"
  fi
  if [[ -z $coxEdgeNodeWorkloadName ]]; then
    techo error "Missing argument --coxedge-node-workload-name"
    error=true
  else
    techo debug "coxEdgeNodeWorkloadName: $coxEdgeNodeWorkloadName"    
  fi
  if [[ -z $coxEdgeNodeWorkloadCount ]]; then
    techo error "Missing argument --coxedge-node-workload-count"
    error=true
  else
    techo debug "coxEdgeNodeWorkloadCount: $coxEdgeNodeWorkloadCount"    
  fi
  if [[ -z $clusterToken ]]; then
    techo error "Missing argument --cluster-token"
    error=true
  else
    techo debug "clusterToken: $clusterToken"    
  fi
  if [[ -z $sshUser ]]; then
    techo error "Missing argument --ssh_user"
    error=true
  else
    techo debug "sshUser: $sshUser"    
  fi
  if [[ $error == true ]]; then
    techo debug "Exiting due to missing arguments"
    exit 1
  fi
}

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

techo() {
  if [[ $1 == debug ]] && [[ $debug == true ]]; then
    echo "$(timestamp): [DEBUG] $2"
  fi
  if [[ $1 == error ]]; then
    echo "$(timestamp): [ERROR] $2"
  fi  
  if [[ $1 == warning ]]; then
    echo "$(timestamp): [WARNING] $2"
  fi
  if [[ $1 == info ]]; then
    echo "$(timestamp): [INFO] $2"
  fi
}

getPrivateIP() {
  techo info "Getting instance internal IP address..."
  private_ip=`curl -s -X GET -H "MC-Api-Key: ${coxEdgeApiKey}" -H "Content-Type: application/json" "https://portal.coxedge.com/api/v2/services/edge-services/${coxEdgeEnvironmentName}/instances/${instance}" | jq -r .data.ipAddress`
  techo info "Instance internal IP address: ${private_ip}"
}

getPublicIP() {
  techo info "Getting instance public IP address..."
  public_ip=`curl -s -X GET -H "MC-Api-Key: ${coxEdgeApiKey}" -H "Content-Type: application/json" "https://portal.coxedge.com/api/v2/services/edge-services/${coxEdgeEnvironmentName}/instances/${instance}" | jq -r .data.publicIpAddress`
  techo info "Instance public IP address: $public_ip"
}

getAnyCastIP() {
  techo debug "Getting instance anycast IP address..."
  anycast_ready=false
  anycast_ip=""
  workloadname=$1
  until [ $anycast_ready = true ]
  do
    anycast_ip=`curl -s -X GET -H "MC-Api-Key: ${coxEdgeApiKey}" -H "Content-Type: application/json" "https://portal.coxedge.com/api/v2/services/edge-services/${coxEdgeEnvironmentName}/workloads/${workloadname}" | jq -r .data.anycastIpAddress`
    techo debug "Current anycast IP: $anycast_ip"
    if [ $anycast_ip = "null" ]
    then
      techo warning "Anycast IP is not ready, sleeping for 10 seconds..."
      sleep 10
    else
      techo info "Anycast IP is ready, continuing..."
      anycast_ready=true
    fi
  done
  techo info "Anycast IP address: ${anycast_ip}"
}

checkInstanceStatus(){
  ready=false
  until [ $ready = true ]
  do
    techo info "Checking if instance is ready..."
    status=`curl -s -X GET -H "MC-Api-Key: ${coxEdgeApiKey}" -H "Content-Type: application/json" "https://portal.coxedge.com/api/v2/services/edge-services/${coxEdgeEnvironmentName}/instances/${instance}" | jq -r .data.status`
    techo debug "Current status: $status"
    if [ $status = "RUNNING" ]
    then
      techo info "Instance is ready, continuing..."
      ready=true
    else
      techo warning "Instance is not ready, sleeping for 10 seconds..."
      sleep 10
    fi
  done
}

checkSSH() {
  techo debug "Checking if SSH is ready by running uptime command..."
  ssh_ready=false
  until [ $ssh_ready = true ]
  do
    techo info "Checking if SSH is ready..."
    output=`ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem ${sshUser}@${public_ip} "uptime"`
    if [ $? -eq 0 ]
    then
      techo info "SSH is ready, continuing..."
      techo debug "SSH output: $output"
      ssh_ready=true
    else
      techo warning "SSH is not ready, sleeping for 10 seconds..."
      techo debug "SSH output: $output"
      sleep 10
    fi
  done
}

setRootSSH() {
  techo info "Setting root SSH access..."
  ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem ${sshUser}@${public_ip} bash <<EOF
sudo cp -r ~/.ssh/ /root/;
sudo chown -R root:root /root/.ssh/
sudo sed -i "s/PermitRootLogin.*/PermitRootLogin\ without-password/g" /etc/ssh/sshd_config
sudo systemctl restart sshd
EOF
  techo info "Checking if root SSH is ready..."
  ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem root@${public_ip} "uptime"
}

patchingOS() {
  techo info "Patching OS..."
  ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem root@${public_ip} bash <<EOF
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::=--force-confdef upgrade -q -y --allow-downgrades --allow-remove-essential --allow-change-held-packages
apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::=--force-confdef dist-upgrade -q -y --allow-downgrades --allow-remove-essential --allow-change-held-packages
reboot
EOF
  techo info "Waiting for instance to reboot..."
  techo debug "Sleeping for 15 seconds..."
  sleep 15
  checkSSH
}

checkrke2() {
  techo debug "Checking if rke2 master is ready by running kubectl get nodes command..."
  rke2_master_ready=false
  until [ $rke2_master_ready = true ]
  do
    techo info "Checking if rke2 master is ready..."
    ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem ${sshUser}@${public_ip} "kubectl get nodes"
    if [ $? -eq 0 ]
    then
      techo info "rke2 master is ready, continuing..."
      rke2_master_ready=true
    else
      techo warning "rke2 master is not ready, sleeping for 10 seconds..."
      sleep 10
    fi
  done
}

checkVMCountMatches() {
  techo debug "Checking if VM count matches..."
  instance_count=$1
  if [ -z $instance_count ]
  then
    techo error "Instance count is not set, exiting..."
    exit 1
  fi
  vm_count_ready=false
  techo info "Desired VM count: $instance_count"
  until [ $vm_count_ready = true ]
  do
    techo info "Checking if VM count matches..."
    vm_count=`curl -s -X GET -H "MC-Api-Key: ${coxEdgeApiKey}" -H "Content-Type: application/json" "https://portal.coxedge.com/api/v2/services/edge-services/${coxEdgeEnvironmentName}/instances?workloadId=${workload_id}" | jq -r .data[].id | wc -l`
    techo debug "Current VM count: $vm_count"
    if [ $vm_count -eq $instance_count ]
    then
        techo "VM count matches, continuing..."
        vm_count_ready=true
    else
        techo "VM count does not match, sleeping for 10 seconds..."
        sleep 10
    fi
  done
  techo debug "VM count matches"
}

getWorkloadID() {
  techo info "Getting workload ID..."
  workloadname=$1
  if [ -z $workloadname ]
  then
    techo error "Workload name is required"
    exit 1
  fi
  techo debug "Workload name: ${workloadname}"
  workload_id=`curl -s -X GET -H "MC-Api-Key: ${coxEdgeApiKey}" -H "Content-Type: application/json" "https://portal.coxedge.com/api/v2/services/edge-services/${coxEdgeEnvironmentName}/workloads/${workloadname}" | jq -r .data.id`
  techo info "Workload ID: ${workload_id}"
}

ARGUMENT_LIST=(
  "coxedge-api-key"
  "coxedge-organization-id"
  "coxedge-environment-name"
  "coxedge-node-workload-name"
  "coxedge-node-workload-count"
  "cluster-token"
  "sshUser"
  "debug"
)

opts=$(getopt \
  --longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
  --name "$(basename "$0")" \
  --options "" \
  -- "$@"
)

eval set --$opts

while [[ $# -gt 0 ]]; do
  case "$1" in
    --coxedge-api-key)
      coxEdgeApiKey=$2
      shift 2
      ;;

    --coxedge-organization-id)
      coxEdgeOrganizationId=$2
      shift 2
      ;;

    --coxedge-environment-name)
      coxEdgeEnvironemtName=$2
      shift 2
      ;;

    --coxedge-node-workload-name)
      coxEdgeNodeWorkloadName=$2
      shift 2
      ;;

    --coxedge-node-workload-count)
      coxEdgeNodeWorkloadCount=$2
      shift 2
      ;;

    --cluster-token)
      clusterToken=$2
      shift 2
      ;;

    --sshUser)
      sshUser=$2
      shift 2
      ;;

    --debug)
      debug=true
      shift 2
      ;;

    *)
      break
      ;;
  esac
done
validatingArguments

techo info "Fixing permissions on private key..."
if [ -f private.pem ]
then
  chmod 600 private.pem
else
  techo error "private.pem not found, exiting..."
  exit 1
fi

techo info "Collecting information about the VMs..."
getWorkloadID ${coxEdgeNodeWorkloadName}
getAnyCastIP ${coxEdgeNodeWorkloadName}
anycast_ip=$anycast_ip
techo debug "Anycast IP for nodes: ${anycast_ip}"

techo info "Making sure all VMs are created..."
checkVMCountMatches ${coxEdgeNodeWorkloadCount}

techo info "Starting rke2 cluster creation for master nodes..."
first=true
curl -s -X GET -H "MC-Api-Key: ${coxEdgeApiKey}" -H "Content-Type: application/json" "https://portal.coxedge.com/api/v2/services/edge-services/${coxEdgeEnvironmentName}/instances?workloadId=${workload_id}" | jq -r .data[].id | sort > nodes.txt
for instance in `cat nodes.txt`
do
  techo debug "Instance ID: $instance"
  getPrivateIP
  getPublicIP
  checkInstanceStatus
  checkSSH
  setRootSSH
  #patchingOS
  if [ $first = true ]
  then
    techo info "Installing rke2 on master node..."
    rke2_bootstrap_ip=${private_ip}
    techo debug "rke2_bootstrap_ip: ${rke2_bootstrap_ip}"
  fi
  techo info "Installing rke2 server on ${public_ip}..."
  ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem root@${public_ip} bash <<EOF
  curl -sfL https://get.rke2.io | sh -
  mkdir -p /etc/rancher/rke2
EOF
  if [ $first = true ]
  then
    techo info "This is the first instance, so we will bootstrap the cluster from here"
    ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem root@${public_ip} bash <<EOF
    echo "#server: https://${rke2_bootstrap_ip}:9345" > /etc/rancher/rke2/config.yaml
EOF
    first=false
  else
    techo info "This is not the first instance, so we will join the cluster"
    techo debug "rke2_bootstrap_ip: ${rke2_bootstrap_ip}"
    ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem root@${public_ip} bash <<EOF
    echo "server: https://${rke2_bootstrap_ip}:9345" > /etc/rancher/rke2/config.yaml
EOF
  fi
  techo info "Finishing rke2 installation on ${public_ip}..."
  ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem root@${public_ip} bash <<EOF
  echo "token: ${clusterToken}" >> /etc/rancher/rke2/config.yaml
  echo "write-kubeconfig-mode: 644" >> /etc/rancher/rke2/config.yaml
  echo "node-ip: ${private_ip}" >> /etc/rancher/rke2/config.yaml
  echo "node-external-ip: ${public_ip}" >> /etc/rancher/rke2/config.yaml
  echo "node-label:" >> /etc/rancher/rke2/config.yaml
  echo "  - coxedge-organization-id=${coxEdgeOrganizationId}" >> /etc/rancher/rke2/config.yaml
  echo "  - coxedge-environment-name=${coxEdgeEnvironmentName}" >> /etc/rancher/rke2/config.yaml
  echo "  - coxedge-workload-id=${workload_id}" >> /etc/rancher/rke2/config.yaml
  echo "  - coxedge-anycast-ip=${anycast_ip}" >> /etc/rancher/rke2/config.yaml
  echo "tls-san:" >> /etc/rancher/rke2/config.yaml
  echo "  - ${public_ip}" >> /etc/rancher/rke2/config.yaml
  echo "  - ${anycast_ip}" >> /etc/rancher/rke2/config.yaml
  echo "Enabling rke2 service..."
  systemctl enable rke2-server.service
  echo "Restarting rke2 service..."
  systemctl start rke2-server.service
  mkdir -p ~/.kube/
  ln -s /etc/rancher/rke2/rke2.yaml ~/.kube/config
  ln -s /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
  echo "Waiting for rke2 to start..."
  sleep 60
  kubectl get nodes -o wide
EOF
  #checkrke2
  techo info "Pulling kubeconfig..."
  ssh -o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null" -i private.pem root@${public_ip} "kubectl config view --flatten" | sed -e "s/127.0.0.1/${anycast_ip}/g" > kubeconfig
done

techo info "All nodes are ready."