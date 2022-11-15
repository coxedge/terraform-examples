#cloud-config
users:
  - name: root
    ssh-authorized-keys:
      - ${ssh_public_key}
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    lock_passwd: true
    shell: /bin/bash
write_files:
  - path: /usr/local/bin/cloud-init.sh
    permissions: '0755'
    owner: root:root
    content: |
      #!/bin/bash
      echo "=========Starting install script========="
      echo "Checking for Lock File..."
      if [ -f /cloud-init.lock ]; then
        echo "Lock File Exists. Exiting..."
        exit 0
      fi
      echo "Getting public IP..."
      PublicIp=`curl -s ifconfig.me. 2>/dev/null`
      echo "Public IP: $PublicIp"
      echo "Getting internal IP..."
      InternalIp=`ip addr show eth0 | grep -Po 'inet \K[\d.]+'`
      echo "Interanl IP: $InternalIp"
      echo "Installing Rancher agent..."
      curl -fL ${rancher_url}/system-agent-install.sh | sudo sh -s - \
      --server ${rancher_url} \
      --label 'cattle.io/os=linux' \
      --token ${cluster_token} \
      --etcd \
      --controlplane \
      --worker \
      --address $PublicIp \
      --internal-address $InternalIp \
      --label coxedge_organization_id=${coxedge_organization_id} \
      --label coxedge_environment_name=${coxedge_environment_name}
      echo "=========Install script complete========="
      echo "=========Starting addon script==========="
      echo "Installing Helm..."
      curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
      echo "Linking kubectl to /usr/local/bin..."
      ln -s /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
      echo "Linking kubeconfig for root..."
      mkdir -p /root/.kube
      ln -s /var/lib/rancher/rke2/server/cred/admin.kubeconfig /root/.kube/config
      echo "Creating Lock File..."
      date > /cloud-init.lock
      echo "=========Finished install script========="
runcmd:
  - [ sh, -c, /usr/local/bin/cloud-init.sh > /var/log/cloud-init-script.log 2>&1 ]