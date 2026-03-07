#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_lib.sh"

echo ""
echo "========================================"
echo " クリーンアップ"
echo "========================================"
echo ""

log "k8s リソースを削除中..."
kubectl delete -f "$SCRIPT_DIR/k8s/deployment-prestop.yaml" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$SCRIPT_DIR/k8s/deployment.yaml" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$SCRIPT_DIR/k8s/service.yaml" --ignore-not-found=true 2>/dev/null || true

log "minikube を停止・削除中..."
minikube stop 2>/dev/null || true
minikube delete 2>/dev/null || true

ok "クリーンアップ完了"
echo ""
