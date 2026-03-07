#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_lib.sh"

echo ""
echo "========================================"
echo " セットアップ: minikube + Docker + Service"
echo "========================================"
echo ""

# 前回の状態をクリーン化
log "前回の状態をクリーンアップ中..."
"$SCRIPT_DIR/cleanup.sh"

# minikube 起動
log "minikube を起動中..."
minikube start
ok "minikube 起動完了"

# minikube の Docker デーモンを使用してイメージビルド
log "minikube の Docker デーモンに切り替え中..."
eval $(minikube docker-env)
ok "Docker デーモン切り替え完了"

log "Docker イメージをビルド中..."
docker build \
    -f "$SCRIPT_DIR/Dockerfile" \
    -t ktor-graceful-shutdown:latest \
    "$PROJECT_ROOT"
ok "Docker イメージビルド完了"

# Service をデプロイ
log "Service をデプロイ中..."
kubectl apply -f "$SCRIPT_DIR/k8s/service.yaml"
ok "Service デプロイ完了"

echo ""
ok "セットアップ完了。verify-pattern1.sh または verify-pattern2.sh を実行してください。"
echo ""
