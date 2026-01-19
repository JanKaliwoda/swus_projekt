# INSTRUKCJE WDRAŻANIA - FAZA II i III

## FAZA II: Wdrożenie aplikacji klient-serwer

### Prerequisites
- Działający klaster Kubernetes z fazy I
- kubectl zainstalowany i skonfigurowany
- Dostęp do master node

### Kroki wdrażania Fazy II

#### 1. Wdrożenie aplikacji serwerowej (Deployment)
```bash
kubectl apply -f fase_II/01-server-deployment.yaml
```

Weryfikacja:
```bash
# Sprawdzenie Deployment
kubectl get deployments -n swus-app

# Sprawdzenie Pods
kubectl get pods -n swus-app

# Logi z aplikacji
kubectl logs -n swus-app -l app=swus-server -f
```

#### 2. Wdrożenie Services (NodePort i ClusterIP)
```bash
kubectl apply -f fase_II/02-server-services.yaml
```

Weryfikacja:
```bash
kubectl get services -n swus-app
```

#### 3. Wdrożenie Pods klientów
```bash
kubectl apply -f fase_II/03-client-pods.yaml
```

Weryfikacja:
```bash
kubectl get pods -n swus-app
```

---

### SCENARIUSZ 2A: Testowanie z Service typu NodePort

#### Konfiguracja
- Service: `swus-server-nodeport`
- Port węzła: 30080
- Wewnętrzny port: 80 (mapuje na 8080 w kontenerze)

#### Test z zewnątrz klastra (SSH na node)

1. Pozyskaj IP węzła worker:
```bash
kubectl get nodes -o wide
# lub z Terraform output
terraform output worker_ip
```

2. Testuj z klienta curl (z poziomu local machine):
```bash
# Zmień <WORKER_NODE_IP> na rzeczywisty IP
curl http://<WORKER_NODE_IP>:30080
curl http://<WORKER_NODE_IP>:30080/health
```

3. Testuj z wewnątrz klastra (z Pod klienta):
```bash
# Wejdź do Pod klienta
kubectl exec -it -n swus-app swus-client-curl -- sh

# Wewnątrz kontenera:
curl http://swus-server-nodeport:80
curl http://swus-server-nodeport.swus-app.svc.cluster.local:80

# Testowanie różnych endpointów
curl -v http://swus-server-nodeport:80/api/test
```

---

### SCENARIUSZ 2B: Testowanie z Service typu ClusterIP

#### Konfiguracja
- Service: `swus-server-clusterip`
- Typ: ClusterIP (tylko wewnętrzny)
- Port: 80 (mapuje na 8080)
- FQDN: `swus-server-clusterip.swus-app.svc.cluster.local`

#### Test z wewnątrz klastra

1. Wejdź do Pod klienta:
```bash
kubectl exec -it -n swus-app swus-client-curl -- sh
```

2. Testuj komunikację (wewnątrz kontenera):
```bash
# Używając nazwy service
curl http://swus-server-clusterip

# Używając pełnego FQDN
curl http://swus-server-clusterip.swus-app.svc.cluster.local

# Testowanie endpointów
curl -v http://swus-server-clusterip/api/endpoints

# Iteracyjne testowanie (dla load balancingu)
for i in {1..10}; do curl http://swus-server-clusterip; echo " - Request $i"; done
```

3. Sprawdzenie którego Poda został obsłużony:
```bash
# W oddzielnym terminalu, obserwuj logi
kubectl logs -n swus-app -l app=swus-server -f
```

#### Test z użyciem k6 (opcjonalnie)

```bash
# Wejdź do k6 pod
kubectl exec -it -n swus-app swus-client-k6 -- sh

# Wewnątrz k6 kontenera, stwórz prosty skrypt
cat > test.js <<EOF
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  vus: 5,
  duration: '10s',
};

export default function () {
  let res = http.get('http://swus-server-clusterip');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
}
EOF

# Uruchomienie testu
k6 run test.js
```

---

## FAZA III: Cilium Cluster Mesh

### Architektura
```
┌─────────────────────┐          ┌──────────────────────┐
│   Cluster 1 (I)     │          │ Cluster 2 (III)      │
│ Pod CIDR: 10.122/16 │◄────────►│ Pod CIDR: 10.132/16  │
│ SVC CIDR: 10.121/16 │          │ SVC CIDR: 10.131/16  │
│                     │          │                      │
│ ┌─────────────────┐ │          │ ┌──────────────────┐ │
│ │  swus-server    │ │          │ │swus-server-v2    │ │
│ │ (Deployment)    │ │          │ │(Deployment)      │ │
│ └─────────────────┘ │          │ └──────────────────┘ │
│ ┌─────────────────┐ │          │ ┌──────────────────┐ │
│ │swus-client-curl │ │          │ │                  │ │
│ │(Pod)            │ │          │ │                  │ │
│ └─────────────────┘ │          │ └──────────────────┘ │
└─────────────────────┘          └──────────────────────┘
        │
        └─────── Cilium Cluster Mesh (VXLAN/Wireguard)
```

### Prerequisites dla Fazy III

1. **Terraform** - Utwórz drugi klaster
```bash
cd c:\kali\swus\projekt\swus_projekt
terraform apply -target=google_compute_instance.master_node_secondary
terraform apply -target=google_compute_instance.worker_node_secondary
terraform apply # aplikuje firewall rules
```

2. **kubectl contexts** - Skonfiguruj dostęp do obu klastrów
```bash
# Pozyskaj kubeconfig z obu masterów
# Z Master Cluster 1:
scp ubuntu@<MASTER_1_IP>:~/.kube/config ./kubeconfig-cluster1

# Z Master Cluster 2:
scp ubuntu@<MASTER_2_IP>:~/.kube/config ./kubeconfig-cluster2

# Połącz kubeconfig (Windows PowerShell):
$env:KUBECONFIG = "kubeconfig-cluster1;kubeconfig-cluster2"
kubectl config get-contexts

# Lub utwórz pliki tymczasowe w KUBECONFIG na każdy klaster
```

### Instalacja Cilium na obu klastrach

#### Na Cluster 1:
```bash
kubectl config use-context cluster-1

# Instalacja Cilium (wymagane Helm)
helm repo add cilium https://helm.cilium.io
helm repo update

# Instalacja z Cluster Mesh enabled
helm install cilium cilium/cilium \
  --namespace cilium \
  --create-namespace \
  --set cluster.id=1 \
  --set cluster.name=cluster-1 \
  --set clustermesh.apiserver.enabled=true \
  --set clustermesh.apiserver.service.type=NodePort \
  --set clustermesh.apiserver.service.nodePort=32379
```

#### Na Cluster 2:
```bash
kubectl config use-context cluster-2

helm install cilium cilium/cilium \
  --namespace cilium \
  --create-namespace \
  --set cluster.id=2 \
  --set cluster.name=cluster-2 \
  --set clustermesh.apiserver.enabled=true \
  --set clustermesh.apiserver.service.type=NodePort \
  --set clustermesh.apiserver.service.nodePort=32379
```

### Konfiguracja Cluster Mesh

1. **Pozyskaj certyfikat z Cluster 2:**
```bash
kubectl config use-context cluster-2

# Pobierz certyfikat
kubectl get secret -n cilium cilium-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

# Pobierz adres IP apiserver
kubectl get svc -n cilium clustermesh-apiserver -o jsonpath='{.spec.clusterIP}'
```

2. **Skonfiguruj Cluster 1:**
```bash
kubectl config use-context cluster-1

# Stwórz secret z certyfikatem z Cluster 2
kubectl create secret generic -n cilium cilium-ca-cluster-2 --from-file=ca.crt

# Utwórz secret z IP apiserver'a Cluster 2
kubectl create secret generic -n cilium clustermesh-secrets-cluster-2 \
  --from-literal=backing-store=etcd \
  --from-literal=api-server-ip=<CLUSTER_2_APISERVER_IP> \
  --from-literal=api-server-port=32379
```

3. **Wdrażanie aplikacji na Cluster 2:**
```bash
kubectl config use-context cluster-2

# Wdrożenie serwera na Cluster 2
kubectl apply -f fase_III/02-server-deployment-secondary.yaml

# Wdrażanie networking policies
kubectl apply -f fase_III/03-cilium-clustermesh-export.yaml
```

### Testowanie komunikacji między klastrami

#### Test 1: Komunikacja przed Service Mesh

1. Z klienta w Cluster 1, spróbuj się połączyć z serverem w Cluster 2:
```bash
kubectl config use-context cluster-1

# Uzyskaj Service IP z Cluster 2
kubectl config use-context cluster-2
kubectl get svc -n swus-app-secondary

# Wróć do Cluster 1 i testuj
kubectl config use-context cluster-1
kubectl exec -it -n swus-app swus-client-curl -- sh

# Wewnątrz:
curl http://swus-server-secondary-clusterip.swus-app-secondary.svc.cluster.local
# Expected: Fail (CIDR nie jest routowany)
```

#### Test 2: Po konfiguracji Cluster Mesh

1. Sprawdź status Cluster Mesh:
```bash
kubectl config use-context cluster-1

cilium status | grep -A 5 "Cluster Mesh"
```

2. Wdrażanie eksportu Service z Cluster 2:
```bash
kubectl config use-context cluster-2

# Service staje się widoczny z innych klastrów
kubectl annotate service swus-server-secondary-clusterip \
  -n swus-app-secondary \
  io.cilium/global-service=true
```

3. Testuj komunikację z Cluster 1:
```bash
kubectl config use-context cluster-1

kubectl exec -it -n swus-app swus-client-curl -- sh

# Wewnątrz - testuj z FQDN
curl http://swus-server-secondary-clusterip.swus-app-secondary.svc.cluster.local

# Testuj wielokrotnie (obserwuj load balancing)
for i in {1..20}; do 
  echo "Request $i:"
  curl http://swus-server-secondary-clusterip.swus-app-secondary.svc.cluster.local
done
```

#### Test 3: Load Balancing z dwoma serwerami

1. Wdrożenie serwera również na Cluster 1:
```bash
kubectl config use-context cluster-1

kubectl apply -f fase_II/01-server-deployment.yaml
```

2. Test load balancingu:
```bash
# Z client poda, wysyłaj wiele requestów
kubectl exec -it -n swus-app swus-client-curl -- sh

# Wewnątrz - obserwuj którym serverem obsługiwany jest request
# Cilium powinien load balancować między instanceami w obu klastrach

curl -v http://swus-server-clusterip.swus-app.svc.cluster.local/hostname
curl -v http://swus-server-secondary-clusterip.swus-app-secondary.svc.cluster.local/hostname

# Iteracyjne testy
for i in {1..10}; do 
  echo "=== Request $i ==="
  curl -s http://swus-server-clusterip.swus-app.svc.cluster.local
done
```

---

## Dokumentacja wyników

Stwórz raport zawierający:

### Dla Fazy II:
- [ ] Zrzuty ekranu/wyniki testów Scenariusza 2A (NodePort)
- [ ] Zrzuty ekranu/wyniki testów Scenariusza 2B (ClusterIP)
- [ ] Wyjaśnienie różnic:
  - NodePort: dostęp z zewnątrz, port na każdym node'cie
  - ClusterIP: dostęp tylko wewnątrz klastra, FQDN DNS
  - Load balancing różnicy
- [ ] Manifesty YAML (01-03 z fase_II)

### Dla Fazy III:
- [ ] Status Cluster Mesh przed i po konfiguracji
- [ ] Testy komunikacji między klastrami
- [ ] Load balancing behavior documentation
- [ ] Wyjaśnienie algorytmu load balancingu w Cilium
- [ ] Porównanie teoretyczne z innymi Service Mesh (Istio, Submariner)

---

## Troubleshooting

### Problem: Pod nie może się połączyć z serwer Service
```bash
# Sprawdzenie DNS w pod
kubectl exec -it <pod> -- nslookup swus-server-clusterip.swus-app.svc.cluster.local

# Sprawdzenie endpoints
kubectl get endpoints -n swus-app

# Logi kubelet
ssh ubuntu@<NODE_IP>
sudo journalctl -u kubelet -f
```

### Problem: Cluster Mesh nie łączy klastrów
```bash
# Sprawdzenie Cilium apiserver
kubectl get pods -n cilium | grep apiserver
kubectl logs -n cilium -l k8s-app=cilium-apiserver

# Sprawdzenie connectivity
kubectl exec -it -n cilium cilium-XXXX -- cilium-dbg endpoint list
```

### Problem: Conntrack lub network issues
```bash
# Reset conntrack (ostrożnie!)
ssh ubuntu@<MASTER_IP>
sudo conntrack -F

# Restart containerd
sudo systemctl restart containerd
sudo systemctl restart kubelet
```
