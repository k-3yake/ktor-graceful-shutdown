#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_lib.sh"

echo ""
echo "========================================"
echo " パターン1: preStop なし"
echo "========================================"
echo ""

# セットアップ確認
check_setup

# minikube の Docker デーモンを使用
eval $(minikube docker-env)

# Deployment をデプロイ
log "deployment.yaml を apply 中..."
kubectl apply -f "$SCRIPT_DIR/k8s/deployment.yaml"

# Pod ready 待ち
log "rollout 完了を待機中..."
kubectl rollout status deployment/ktor-app --timeout=120s
wait_for_pod_ready

# テスト実行
RESULT=$(run_test "パターン1" "$LOGS_DIR/pattern1.log")

# タイムライン表示
print_timeline "パターン1: preStop なし (結果: HTTP $RESULT)" "$LOGS_DIR/pattern1.log"

echo ""
echo "========================================"
echo " パターン1 結果"
echo "========================================"
echo ""
echo -n "パターン1 (preStop なし): "
if [ "$RESULT" = "200" ]; then
    echo -e "${GREEN}HTTP 200 (正常完了)${NC}"
else
    echo -e "${RED}HTTP $RESULT (リクエスト中断)${NC}"
fi

echo ""
echo "期待結果: HTTP 000 (接続エラー) ← グレースフルシャットダウンが壊れているため"
echo ""
log "ログファイル: $LOGS_DIR/pattern1.log"
log "リソースはそのまま残しています。kubectl logs / kubectl describe で調査可能です。"
echo ""
