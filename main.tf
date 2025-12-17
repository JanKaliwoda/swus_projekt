# Configure the Google Cloud provider
provider "google" {
  project = var.gcp_project_id
  zone    = var.gcp_zone
}

# --- Compute Engine Instances (VMs) ---

# Master Node VM
resource "google_compute_instance" "master_node" {
  name         = "kube-master"
  machine_type = "e2-standard-2"
  zone         = var.gcp_zone
  tags         = ["kube-node", "master", "http-server", "https-server"]

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

echo "--- Installing Prerequisites ---"
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Install containerd (recommended over full Docker for K8s)
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

echo "--- Initializing K8s Cluster (Kubeadm) ---"
# UŻYCIE TWOICH PARAMETRÓW: Service CIDR: 10.121.0.0/16, Pod CIDR: 10.122.0.0/16
sudo kubeadm init --pod-network-cidr=10.122.0.0/16 --service-cidr=10.121.0.0/16 --node-name=kube-master

# Configure kubectl for root and default user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /etc/profile.d/k8s.sh
export KUBECONFIG=/etc/kubernetes/admin.conf

# Install Cilium CLI (to fulfill CNI requirement)
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=$(dpkg --print-architecture)
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/$${CILIUM_CLI_VERSION}/cilium-linux-$${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-$${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-$${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-$${CLI_ARCH}.tar.gz{,.sha256sum}

# UWAGA: Cilium install zostanie wykonane manualnie lub przez Helm po dołączeniu workera.
echo "Kubernetes master setup completed."
EOF
}

# Worker Node VM
resource "google_compute_instance" "worker_node" {
  name         = "kube-worker"
  machine_type = "e2-standard-4" # Zgodnie z wymaganiem (4 vCPU, 16 GB RAM)
  zone         = var.gcp_zone
  tags         = ["kube-node", "worker"]

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

  # Uproszczony skrypt dla Workera (tylko instalacja, bez kubeadm init)
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
cat <<SYSCTL_EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
SYSCTL_EOF
sudo sysctl --system
EOF
}

# --- Firewall Rules ---

resource "google_compute_firewall" "allow_kubernetes_internal" {
  name    = "allow-k8s-internal"
  network = "default"

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
  source_tags = ["kube-node"]
}

resource "google_compute_firewall" "allow_ssh_external" {
  name    = "allow-ssh-external"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "6443"] # SSH + API Server
  }
  source_ranges = ["0.0.0.0/0"]
}

# --- Outputs ---

output "master_ip" {
  value = google_compute_instance.master_node.network_interface[0].access_config[0].nat_ip
}

output "worker_ip" {
  value = google_compute_instance.worker_node.network_interface[0].access_config[0].nat_ip
}

output "join_command_instruction" {
  value = "Po zalogowaniu na Mastera przez SSH, wpisz: 'sudo kubeadm token create --print-join-command', a następnie wykonaj wynik na Workerze."
}