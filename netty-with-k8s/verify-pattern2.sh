#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/_lib.sh"

echo ""
echo "========================================"
echo " パターン2: preStop sleep 15"
echo "========================================"
echo ""

# セットアップ確認
check_setup

# minikube の Docker デーモンを使用
eval $(minikube docker-env)

# 既存の Deployment を削除して完全クリーン
log "既存の Deployment を削除中..."
kubectl delete -f "$SCRIPT_DIR/k8s/deployment.yaml" --ignore-not-found=true 2>/dev/null || true
kubectl delete -f "$SCRIPT_DIR/k8s/deployment-prestop.yaml" --ignore-not-found=true 2>/dev/null || true

# 全Podが消えるまで待機
log "既存Podの完全終了を待機中..."
while [ "$(kubectl get pods -l app=ktor-app --no-headers 2>/dev/null | wc -l)" -gt 0 ]; do
    sleep 2
done
ok "既存Podがすべて終了しました"

# deployment-prestop.yaml をデプロイ
log "deployment-prestop.yaml を apply 中..."
kubectl apply -f "$SCRIPT_DIR/k8s/deployment-prestop.yaml"

# Pod ready 待ち
log "rollout 完了を待機中..."
kubectl rollout status deployment/ktor-app --timeout=120s
wait_for_pod_ready

# テスト実行
RESULT=$(run_test "パターン2" "$LOGS_DIR/pattern2.log")

# タイムライン表示
print_timeline "パターン2: preStop sleep 15 (結果: HTTP $RESULT)" "$LOGS_DIR/pattern2.log"

echo ""
echo "========================================"
echo " パターン2 結果"
echo "========================================"
echo ""
echo -n "パターン2 (preStop sleep 15): "
if [ "$RESULT" = "200" ]; then
    echo -e "${GREEN}HTTP 200 (正常完了)${NC}"
else
    echo -e "${RED}HTTP $RESULT (リクエスト中断)${NC}"
fi

echo ""
echo "期待結果: HTTP 200 (正常完了) ← preStop sleep 中にリクエストが完了するため"
echo ""
log "ログファイル: $LOGS_DIR/pattern2.log"
log "リソースはそのまま残しています。kubectl logs / kubectl describe で調査可能です。"
echo ""
