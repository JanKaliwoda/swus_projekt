# PODSUMOWANIE FAZA II i III - Projekt SWUS

## 📋 Struktura Katalogów

```
c:\kali\swus\projekt\swus_projekt\
├── main.tf                          # Konfiguracja Cluster 1 (Faza I)
├── secondary_cluster.tf             # Konfiguracja Cluster 2 (Faza III)
├── variables.tf                     # Zmienne Terraform
├── terraform.tfstate*               # Stan Terraform
│
├── fase_II/                         # Faza II - Manifesty Kubernetes
│   ├── 01-server-deployment.yaml    # Deployment serwera (2 repliki)
│   ├── 02-server-services.yaml      # NodePort + ClusterIP Services
│   └── 03-client-pods.yaml          # Client Pods (curl, k6)
│
├── fase_III/                        # Faza III - Cilium Cluster Mesh
│   ├── 01-cilium-namespace-rbac.yaml
│   ├── 02-server-deployment-secondary.yaml
│   └── 03-cilium-clustermesh-export.yaml
│
├── scripts/                         # Skrypty pomocnicze
│   ├── deploy-phase2.sh            # Deploy Faza II (Linux/Mac)
│   ├── deploy-phase2.ps1           # Deploy Faza II (Windows)
│   ├── test-nodeport.sh            # Testowanie NodePort
│   ├── test-clusterip.sh           # Testowanie ClusterIP
│   ├── setup-multicluster-kubeconfig.sh
│   └── setup-cilium-clustermesh.sh # Automatyczna konfiguracja mesh
│
└── INSTRUKCJE_FAZA_II_III.md        # Ta dokumentacja
```

---

## 🚀 Quick Start

### Faza II (Test Aplikacji Klient-Serwer)

#### Linux/Mac:
```bash
cd c:\kali\swus\projekt\swus_projekt
chmod +x scripts/*.sh
./scripts/deploy-phase2.sh
```

#### Windows PowerShell:
```powershell
cd c:\kali\swus\projekt\swus_projekt
.\scripts\deploy-phase2.ps1
```

### Faza III (Cilium Cluster Mesh)

```bash
# Terraform - utwórz drugi klaster
terraform apply

# Automatyczna konfiguracja Cilium mesh
./scripts/setup-cilium-clustermesh.sh
```

---

## 📊 Parametry Klastrów

### Cluster 1 (Faza I & II)
| Parametr | Wartość |
|----------|---------|
| Nazwa | kube-master / kube-worker |
| Strefa GCP | europe-west3-a |
| Pod CIDR | 10.122.0.0/16 |
| Service CIDR | 10.121.0.0/16 |
| Master machine | e2-standard-2 (2 vCPU, 8 GB) |
| Worker machine | e2-standard-4 (4 vCPU, 16 GB) |

### Cluster 2 (Faza III)
| Parametr | Wartość |
|----------|---------|
| Nazwa | kube-master-secondary / kube-worker-secondary |
| Strefa GCP | europe-west3-b |
| Pod CIDR | 10.132.0.0/16 |
| Service CIDR | 10.131.0.0/16 |
| Master machine | e2-standard-2 (2 vCPU, 8 GB) |
| Worker machine | e2-standard-4 (4 vCPU, 16 GB) |

---

## 🔍 Faza II - Scenariusze Testowania

### Scenariusz 2A: Service NodePort

**Charakterystyka:**
- ✅ Dostęp z **zewnątrz klastra**
- ✅ Port udostępniany na **każdym node'cie** (30080)
- ✅ Load balancing: round-robin na Pody
- ❌ Brak DNS names z zewnątrz

**Test:**
```bash
# Pozyskaj IP worker node
WORKER_IP=$(terraform output worker_ip)

# Testuj z zewnątrz
curl http://$WORKER_IP:30080

# Testuj z wewnątrz pod
kubectl exec -it -n swus-app swus-client-curl -- sh
# wewnątrz:
curl http://swus-server-nodeport:80
```

**Obserwacje:**
- Load balancing między replikami Deployment
- Każdy request może trafić na inny Pod
- Dostępny port na każdym node'cie klastra

### Scenariusz 2B: Service ClusterIP

**Charakterystyka:**
- ✅ Dostęp tylko **wewnątrz klastra**
- ✅ **DNS name** (FQDN)
- ✅ Load balancing między Podami
- ✅ Skalowalne i fleksybilne
- ❌ Niedostępny z poza klastra

**Test:**
```bash
# Wejdź do pod
kubectl exec -it -n swus-app swus-client-curl -- sh

# Testuj wewnątrz
curl http://swus-server-clusterip  # short name
curl http://swus-server-clusterip.swus-app.svc.cluster.local  # FQDN

# Obserwuj logi serwerów
kubectl logs -n swus-app -l app=swus-server -f
```

**Obserwacje:**
- DNS resolution do service IP
- Load balancing między dostępnymi Podami
- Każdy request rozdzielony między repliki

### Porównanie 2A vs 2B

| Cecha | NodePort | ClusterIP |
|-------|----------|-----------|
| Dostęp z zewnątrz | ✅ Tak | ❌ Nie |
| Port na każdym node | ✅ Tak | ❌ N/A |
| DNS wewnętrzny | ⚠️ Opcjonalnie | ✅ Tak |
| Load balancing | ✅ Round-robin | ✅ Round-robin |
| Bezpieczeństwo | ⚠️ Otwarte | ✅ Bezpieczne |
| Use case | Testy, expose API | Produkcja |

---

## 🔗 Faza III - Cilium Cluster Mesh

### Architektura

```
┌──────────────────────────────────────────────────────────┐
│                   Cluster 1 (Primary)                     │
│  Pods: 10.122.0.0/16  |  Services: 10.121.0.0/16       │
│                                                            │
│  ┌─────────────────┐         ┌──────────────────┐        │
│  │  swus-server    │         │  Cilium CNI      │        │
│  │ (2 repliki)     │         │  + Cluster Mesh  │        │
│  └─────────────────┘         └──────────────────┘        │
│  ┌─────────────────┐                                      │
│  │  swus-client    │                                      │
│  │ (curl, k6)      │                                      │
│  └─────────────────┘                                      │
└──────────────────────────────────────────────────────────┘
                         ↕ VXLAN/Wireguard
┌──────────────────────────────────────────────────────────┐
│                  Cluster 2 (Secondary)                    │
│  Pods: 10.132.0.0/16  |  Services: 10.131.0.0/16       │
│                                                            │
│  ┌─────────────────────┐      ┌──────────────────┐       │
│  │  swus-server-v2     │      │  Cilium CNI      │       │
│  │ (2 repliki)         │      │  + Cluster Mesh  │       │
│  └─────────────────────┘      └──────────────────┘       │
└──────────────────────────────────────────────────────────┘
```

### Etapy Implementacji

#### 1️⃣ Instalacja Cilium na obu klastrach
```bash
# Cluster 1
helm install cilium cilium/cilium \
  --namespace cilium --create-namespace \
  --set cluster.id=1 --set cluster.name=cluster-1 \
  --set clustermesh.apiserver.enabled=true

# Cluster 2
helm install cilium cilium/cilium \
  --namespace cilium --create-namespace \
  --set cluster.id=2 --set cluster.name=cluster-2 \
  --set clustermesh.apiserver.enabled=true
```

#### 2️⃣ Konfiguracja komunikacji między klastrami
```bash
# Pobierz CA z Cluster 2
kubectl get secret -n cilium cilium-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

# Skonfiguruj Cluster 1
kubectl create secret generic -n cilium clustermesh-secrets-cluster-2 \
  --from-file=ca.crt --from-literal=api-server-ip=<IP> \
  --from-literal=api-server-port=32379
```

#### 3️⃣ Export Service z Cluster 2
```bash
# Oznacz service jako globalny
kubectl annotate service swus-server-secondary-clusterip \
  -n swus-app-secondary io.cilium/global-service=true
```

#### 4️⃣ Test komunikacji
```bash
# Z Cluster 1, połącz się do Cluster 2
kubectl exec -it -n swus-app swus-client-curl -- sh
curl swus-server-secondary-clusterip.swus-app-secondary.svc.cluster.local
```

### Load Balancing w Cilium Cluster Mesh

**Obserwacje:**
- Cilium robi load balancing **między Podami w obu klastrach**
- Algorytm: `Maglev consistent hashing` (opuszczalny round-robin)
- Connection tracking w ebpf kernel
- Auto-failover na inny klaster jeśli jeden jest down

**Test load balancingu:**
```bash
# Z klienta, wysłanie wielokrotnych requestów
for i in {1..100}; do
  curl -s swus-server-secondary-clusterip.swus-app-secondary.svc.cluster.local | grep -o "Pod:[^<]*"
done | sort | uniq -c
```

**Oczekiwany rezultat:**
```
~25 Pod-A (Cluster 1)
~25 Pod-B (Cluster 1)
~25 Pod-A (Cluster 2)
~25 Pod-B (Cluster 2)
```

### Porównanie Service Mesh

| Feature | Cilium | Istio | Submariner |
|---------|--------|-------|-----------|
| eBPF | ✅ Tak | ❌ Nie | ❌ Nie |
| Load Balancing | Maglev | Ring Hash | Hash-based |
| Setup | Prosty | Złożony | Średni |
| Performance | Wysoka | Średnia | Średnia |
| Learning Curve | Łatwa | Trudna | Średnia |

---

## 📝 Checklist Testowania

### Faza II - NodePort
- [ ] Deployment uruchomiony (2 repliki)
- [ ] Service NodePort istnieje
- [ ] Port 30080 dostępny na worker node
- [ ] curl z zewnątrz działa
- [ ] Load balancing działa (request trafia na inne Pody)
- [ ] Logi serwera pokazują incoming requests

### Faza II - ClusterIP
- [ ] Service ClusterIP istnieje
- [ ] Client pod może się podłączyć
- [ ] DNS resolution działa
- [ ] FQDN service_name.ns.svc.cluster.local działa
- [ ] Load balancing między Podami
- [ ] Serwer zwracaResponse code 200

### Faza III - Cluster Mesh
- [ ] Terraform stworzył Cluster 2
- [ ] Cilium zainstalowany na obu klastrach
- [ ] Cluster Mesh API server uruchomiony
- [ ] CA certyfikaty wymieniane między klastrami
- [ ] Service eksportowany z Cluster 2
- [ ] Client z Cluster 1 może połączyć się do serwerów w Cluster 2
- [ ] Load balancing między klastrami
- [ ] Failover działa (wysyłanie requestów, jeśli jeden klaster down)

---

## 🛠️ Troubleshooting

### Problem: Pod nie startuje
```bash
kubectl describe pod <pod-name> -n swus-app
kubectl logs <pod-name> -n swus-app
```

### Problem: DNS nie rozwiązuje FQDN
```bash
# Z wewnątrz poda
nslookup swus-server-clusterip.swus-app.svc.cluster.local
# Sprawdzenie CoreDNS
kubectl get pods -n kube-system | grep dns
```

### Problem: Cluster Mesh nie łączy się
```bash
# Sprawdzenie Cilium
kubectl get pods -n cilium -l k8s-app=cilium
kubectl logs -n cilium -l k8s-app=cilium-apiserver
```

### Problem: Load Balancing nie funkcjonuje
```bash
# Sprawdzenie endpoints
kubectl get endpoints -n swus-app swus-server-clusterip
kubectl get endpoints -n swus-app-secondary swus-server-secondary-clusterip

# Sprawdzenie Cilium load balancing
kubectl exec -it -n cilium cilium-xxxxx -- cilium-dbg service list
```

---

## 📚 Dokumentacja dla Raportu

Raport powinien zawierać:

### Część 1: Faza II
1. **Scenariusz 2A (NodePort)**
   - Architektura (diagram)
   - Procedura testowania
   - Wyniki (screenshoty curl output)
   - Analiza load balancingu
   
2. **Scenariusz 2B (ClusterIP)**
   - Architektura (diagram)
   - Procedura testowania
   - Wyniki DNS resolution
   - Wyniki load balancingu
   
3. **Porównanie 2A vs 2B**
   - Tabela cech
   - Kiedy używać każdego
   - Spostrzeżenia z testów

### Część 2: Faza III
1. **Architektura Cluster Mesh**
   - Diagram sieci
   - CIDR ranges
   - Encryption (TLS/Wireguard)
   
2. **Procedura wdrażania**
   - Kroki instalacji Cilium
   - Konfiguracja mesh
   - Export service
   
3. **Wyniki testów**
   - Komunikacja między klastrami
   - Load balancing results
   - Failover behavior
   
4. **Analiza load balancingu**
   - Obserwacje Cilium Maglev
   - Porównanie z innymi mesh'ami
   - Performance metrics

### Manifesty YAML
- Dołączyć wszystkie pliki z `fase_II/` i `fase_III/`
- Opisać każdy manifest
- Wyjaśnić konfigurację

---

## 🎯 Cele Projektu

✅ **Faza I - Completed:**
- Utworzenie klastra Kubernetes (kubeadm)
- Konfiguracja infrastruktury (Terraform)
- Master + Worker node z Cilium CNI

✅ **Faza II - To Do:**
- Deployment aplikacji server (Deployment)
- Deployment aplikacji client (Pods)
- Testowanie NodePort
- Testowanie ClusterIP
- Dokumentacja różnic

✅ **Faza III - To Do:**
- Drugi klaster Kubernetes
- Instalacja Cilium Cluster Mesh
- Export service między klastrami
- Load balancing testy
- Dokumentacja behavior

---

## 📞 Supportive Resources

- [Kubernetes Documentation](https://kubernetes.io/docs)
- [Cilium Cluster Mesh Guide](https://docs.cilium.io/en/v1.14/gettingstarted/clustermesh/)
- [Istio Service Mesh](https://istio.io) (dla porównania)
- [Submariner Multi-Cluster](https://submariner.io) (dla porównania)

---

**Ostatnia aktualizacja:** 2025-01-03  
**Wersja:** 1.0  
**Status:** Ready for Phase II & III Implementation
