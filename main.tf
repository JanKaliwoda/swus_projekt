# Configure the Google Cloud provider
provider "google" {
  project = var.gcp_project_id
  zone    = var.gcp_zone
}

# --- Compute Engine Instances (VMs) ---

# Master Node VM
# Master Node VM
resource "google_compute_instance" "master_node" {
  name         = "kube-master"
  machine_type = "e2-standard-2" # Sufficient for master in a lab environment
  zone         = var.gcp_zone
  tags         = ["kube-node", "http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-lts"
      size  = 50 # GB
    }
  }

  network_interface {
    network = "default" # Using the default VPC network
    access_config {
      # Assign a public IP address for SSH access
    }
  }

  # Startup script to install Docker, kubelet, kubeadm, kubectl, and configure prerequisites
metadata_startup_script = <<EOF
#!/bin/bash
set -e
exec > >(tee /var/log/startup-script.log)
exec 2>&1

echo "Starting Kubernetes node setup..."

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

echo "Configuring Docker daemon..."
sudo tee /etc/docker/daemon.json > /dev/null <<'DOCKER_EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
DOCKER_EOF
sudo systemctl enable docker
sudo systemctl daemon-reload
sudo systemctl restart docker

echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "Installing Kubernetes components..."
# Poprawne repozytorium dla nowszych wersji Ubuntu
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Alternatywnie, możesz użyć starszej metody (ale zaktualizowanej):
# curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
# echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "Configuring kernel networking..."
sudo tee /etc/modules-load.d/k8s.conf > /dev/null <<'MODULES_EOF'
br_netfilter
MODULES_EOF

sudo tee /etc/sysctl.d/k8s.conf > /dev/null <<'SYSCTL_EOF'
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
SYSCTL_EOF
sudo sysctl --system

echo "Kubernetes node setup completed successfully"
EOF
}

# Worker Node VM
resource "google_compute_instance" "worker_node" {
  name         = "kube-worker"
  machine_type = "e2-standard-4" # As required by your task
  zone         = var.gcp_zone
  tags         = ["kube-node"]

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-lts"
      size  = 50 # GB
    }
  }

  network_interface {
    network = "default" # Using the default VPC network
    access_config {} # Assign a public IP address for SSH access
  }

  # Use the same startup script as the master node for prerequisites
  metadata_startup_script = google_compute_instance.master_node.metadata_startup_script
}

# --- Firewall Rules ---

# Allow Kubernetes internal communication and NodePort range
resource "google_compute_firewall" "allow_kubernetes_ports" {
  name    = "allow-kubernetes-ports"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["6443", "2379-2380", "10250", "10251", "10252"] # Master ports
  }
  allow {
    protocol = "tcp"
    ports    = ["10250", "30000-32767"] # Worker ports (NodePort range)
  }
  allow {
    protocol = "udp"
    ports    = ["8285", "8472"] # Common CNI specific ports (e.g., Flannel, Calico)
  }
  allow {
    protocol = "icmp" # For pings
  }
  source_tags = ["kube-node"] # Apply to VMs with 'kube-node' tag
  target_tags = ["kube-node"] # Apply to VMs with 'kube-node' tag
}

# Allow SSH, HTTP, HTTPS from anywhere (for initial setup and potential web services)
resource "google_compute_firewall" "allow_ssh_http_https" {
  name    = "allow-ssh-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }
  source_ranges = ["0.0.0.0/0"] # Be more restrictive in production (e.g., your IP address)
  target_tags   = ["http-server", "https-server"] # Apply only to nodes that need it (master)
}

# --- Outputs ---

# Output the public IP addresses of the master and worker nodes for easy access
output "master_public_ip" {
  value       = google_compute_instance.master_node.network_interface[0].access_config[0].nat_ip
  description = "The public IP address of the Kubernetes master node."
}

output "worker_public_ip" {
  value       = google_compute_instance.worker_node.network_interface[0].access_config[0].nat_ip
  description = "The public IP address of the Kubernetes worker node."
}