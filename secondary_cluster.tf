# Configure the Google Cloud provider for second cluster
provider "google" {
  alias   = "secondary"
  project = var.gcp_project_id
  zone    = var.gcp_zone_secondary
}

# --- Compute Engine Instances for Secondary Cluster (Phase III) ---

# Master Node VM - Secondary Cluster
resource "google_compute_instance" "master_node_secondary" {
  provider     = google.secondary
  name         = "kube-master-secondary"
  machine_type = "e2-standard-2"
  zone         = var.gcp_zone_secondary
  tags         = ["kube-node-secondary", "master-secondary", "http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-lts"
      size  = 50
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata_startup_script = <<EOF
#!/bin/bash
set -e
exec > >(tee /var/log/startup-script.log)
exec 2>&1

echo "--- Installing Prerequisites for Secondary Cluster ---"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Install containerd
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y containerd.io

# Configure containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

echo "--- Disabling swap ---"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "--- Installing Kubernetes components ---"
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet

echo "--- Configuring kernel networking ---"
cat <<MODULES_EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
overlay
MODULES_EOF
sudo modprobe br_netfilter
sudo modprobe overlay

cat <<SYSCTL_EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
SYSCTL_EOF
sudo sysctl --system

echo "--- Initializing K8s Cluster (Kubeadm) - Secondary ---"
# SECONDARY CLUSTER: Service CIDR: 10.131.0.0/16, Pod CIDR: 10.132.0.0/16
sudo kubeadm init --pod-network-cidr=10.132.0.0/16 --service-cidr=10.131.0.0/16 --node-name=kube-master-secondary

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /etc/profile.d/k8s.sh
export KUBECONFIG=/etc/kubernetes/admin.conf

# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=$(dpkg --print-architecture)
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/$${CILIUM_CLI_VERSION}/cilium-linux-$${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-$${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-$${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-$${CLI_ARCH}.tar.gz{,.sha256sum}

echo "Secondary cluster setup completed."
EOF
}

# Worker Node VM - Secondary Cluster
resource "google_compute_instance" "worker_node_secondary" {
  provider     = google.secondary
  name         = "kube-worker-secondary"
  machine_type = "e2-standard-4"
  zone         = var.gcp_zone_secondary
  tags         = ["kube-node-secondary", "worker-secondary"]

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-lts"
      size  = 50
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata_startup_script = <<EOF
#!/bin/bash
set -e
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y containerd.io
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
cat <<SYSCTL_EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
SYSCTL_EOF
sudo sysctl --system
EOF
}

# --- Firewall Rules for Secondary Cluster ---

resource "google_compute_firewall" "allow_kubernetes_internal_secondary" {
  provider = google.secondary
  name     = "allow-k8s-internal-secondary"
  network  = "default"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }
  source_tags = ["kube-node-secondary"]
}

resource "google_compute_firewall" "allow_ssh_external_secondary" {
  provider = google.secondary
  name     = "allow-ssh-external-secondary"
  network  = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "6443"]
  }
  source_ranges = ["0.0.0.0/0"]
}

# --- Outputs for Secondary Cluster ---

output "master_ip_secondary" {
  value = google_compute_instance.master_node_secondary.network_interface[0].access_config[0].nat_ip
}

output "worker_ip_secondary" {
  value = google_compute_instance.worker_node_secondary.network_interface[0].access_config[0].nat_ip
}

output "join_command_instruction_secondary" {
  value = "Po zalogowaniu na Masterze (secondary) przez SSH, wpisz: 'sudo kubeadm token create --print-join-command', a następnie wykonaj wynik na Workerze (secondary)."
}

resource "google_compute_firewall" "allow_cilium_clustermesh" {
  name    = "allow-cilium-clustermesh"
  network = "default"

  # Komunikacja tunelowa (VXLAN)
  allow {
    protocol = "udp"
    ports    = ["8472"]
  }
  # Komunikacja API ClusterMesh (NodePort)
  allow {
    protocol = "tcp"
    ports    = ["32379"]
  }

  # Zezwalamy na ruch z obu grup (Klaster 1 i Klaster 2)
  source_tags = ["kube-node", "kube-node-secondary"]
  target_tags = ["kube-node", "kube-node-secondary"]
}
