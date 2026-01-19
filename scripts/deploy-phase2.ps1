#!/bin/bash
# PowerShell version for Windows users
# Quick deployment script for Phase II
# Usage: .\deploy-phase2.ps1

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Phase II - Quick Deployment (Windows)" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check kubectl
$kubeCtl = Get-Command kubectl -ErrorAction SilentlyContinue
if (-not $kubeCtl) {
    Write-Host "ERROR: kubectl not found" -ForegroundColor Red
    exit 1
}

Write-Host "1. Creating namespace and Deployment..." -ForegroundColor Yellow
kubectl apply -f fase_II/01-server-deployment.yaml

Write-Host ""
Write-Host "2. Creating Services (NodePort + ClusterIP)..." -ForegroundColor Yellow
kubectl apply -f fase_II/02-server-services.yaml

Write-Host ""
Write-Host "3. Creating Client Pods..." -ForegroundColor Yellow
kubectl apply -f fase_II/03-client-pods.yaml

Write-Host ""
Write-Host "4. Waiting for Pods to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Deployment Status:" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
kubectl get all -n swus-app

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Service Details:" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
kubectl get svc -n swus-app

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "Test NodePort (Scenario 2A):" -ForegroundColor Green
Write-Host "  1. Get worker node IP: kubectl get nodes -o wide"
Write-Host "  2. Or use Terraform output: terraform output worker_ip"
Write-Host "  3. Test: curl http://<WORKER_IP>:30080"
Write-Host ""
Write-Host "Test ClusterIP (Scenario 2B):" -ForegroundColor Green
Write-Host "  1. Enter client pod: kubectl exec -it -n swus-app swus-client-curl -- sh"
Write-Host "  2. Inside pod, test: curl http://swus-server-clusterip.swus-app.svc.cluster.local"
Write-Host "=========================================" -ForegroundColor Cyan
