#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()  { echo -e "${GREEN}[OK]${NC} $*"; }
ng()  { echo -e "${RED}[NG]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }

RESULT_PATTERN1=""
RESULT_PATTERN2=""

cleanup() {
    log "クリーンアップ中..."
    kubectl delete -f "$SCRIPT_DIR/k8s/service.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$SCRIPT_DIR/k8s/deployment.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$SCRIPT_DIR/k8s/deployment-prestop.yaml" --ignore-not-found=true 2>/dev/null || true
}

wait_for_pod_ready() {
    log "Podがreadyになるのを待機中..."
    local retries=0
    while ! kubectl wait --for=condition=ready pod -l app=ktor-app --timeout=60s 2>/dev/null; do
        retries=$((retries + 1))
        if [ $retries -ge 5 ]; then
            ng "Podがreadyになりませんでした"
            kubectl get pods -l app=ktor-app
            kubectl describe pod -l app=ktor-app | tail -20
            return 1
        fi
        log "リトライ中... ($retries/5)"
        sleep 5
    done
    ok "Podがreadyになりました"
}

get_service_url() {
    minikube service ktor-app --url 2>/dev/null
}

run_test() {
    local pattern_name="$1"
    local url
    url=$(get_service_url)
    log "Service URL: $url" >&2

    # ヘルスチェック
    local health_status
    health_status=$(curl -s -o /dev/null -w "%{http_code}" "$url/health" 2>/dev/null || echo "000")
    if [ "$health_status" != "200" ]; then
        ng "ヘルスチェック失敗 (HTTP $health_status)" >&2
        echo "000"
        return
    fi
    ok "ヘルスチェック成功" >&2

    # /slow にリクエスト送信（バックグラウンド）
    log "/slow にリクエスト送信中（10秒かかる処理）..." >&2
    local tmpfile
    tmpfile=$(mktemp)
    curl -s -o /dev/null -w "%{http_code}" "$url/slow" > "$tmpfile" 2>/dev/null &
    local curl_pid=$!

    # 2秒待ってから rollout restart
    sleep 2
    log "kubectl rollout restart 実行..." >&2
    kubectl rollout restart deployment/ktor-app >&2

    # curl の完了を待つ
    log "リクエスト完了を待機中..." >&2
    wait $curl_pid || true
    local http_status
    http_status=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ -z "$http_status" ] || [ "$http_status" = "000" ]; then
        ng "$pattern_name: 接続エラー (HTTP 000 / connection refused)" >&2
        echo "000"
    elif [ "$http_status" = "200" ]; then
        ok "$pattern_name: HTTP $http_status (正常完了)" >&2
        echo "200"
    else
        warn "$pattern_name: HTTP $http_status" >&2
        echo "$http_status"
    fi
}

# ====================
# メイン処理
# ====================

echo ""
echo "========================================"
echo " Ktor + k8s グレースフルシャットダウン検証"
echo "========================================"
echo ""

# 1. minikube 起動
log "minikube の状態を確認中..."
if minikube status | grep -q "Running" 2>/dev/null; then
    ok "minikube は既に起動中"
else
    log "minikube を起動中..."
    minikube start
    ok "minikube 起動完了"
fi

# 2. minikube の Docker デーモンを使用
log "minikube の Docker デーモンに切り替え中..."
eval $(minikube docker-env)
ok "Docker デーモン切り替え完了"

# 3. Docker イメージビルド（プロジェクトルートをコンテキストに使用）
log "Docker イメージをビルド中..."
docker build \
    -f "$SCRIPT_DIR/Dockerfile" \
    -t ktor-graceful-shutdown:latest \
    "$PROJECT_ROOT"
ok "Docker イメージビルド完了"

# 4. k8s リソースをデプロイ
log "k8s リソースをデプロイ中..."
kubectl apply -f "$SCRIPT_DIR/k8s/service.yaml"
kubectl apply -f "$SCRIPT_DIR/k8s/deployment.yaml"

# 5. Pod ready 待ち
wait_for_pod_ready

# ====================
# パターン1: preStop なし
# ====================
echo ""
echo "----------------------------------------"
echo " パターン1: preStop なし"
echo "----------------------------------------"
echo ""

RESULT_PATTERN1=$(run_test "パターン1")

# rollout が完了するまで待機
log "rollout 完了を待機中..."
kubectl rollout status deployment/ktor-app --timeout=120s
wait_for_pod_ready

# ====================
# パターン2: preStop sleep 15
# ====================
echo ""
echo "----------------------------------------"
echo " パターン2: preStop sleep 15"
echo "----------------------------------------"
echo ""

log "deployment-prestop.yaml に差し替え中..."
kubectl apply -f "$SCRIPT_DIR/k8s/deployment-prestop.yaml"

# 新しい Pod が ready になるまで待機
log "rollout 完了を待機中..."
kubectl rollout status deployment/ktor-app --timeout=120s
wait_for_pod_ready

RESULT_PATTERN2=$(run_test "パターン2")

# ====================
# 結果表示
# ====================
echo ""
echo "========================================"
echo " 検証結果"
echo "========================================"
echo ""
echo "Ktor バージョン: 3.4.0 (グレースフルシャットダウンが壊れている)"
echo ""

STATUS1="$RESULT_PATTERN1"
STATUS2="$RESULT_PATTERN2"

echo -n "パターン1 (preStop なし):      "
if [ "$STATUS1" = "200" ]; then
    echo -e "${GREEN}HTTP 200 (正常完了)${NC}"
else
    echo -e "${RED}HTTP $STATUS1 (リクエスト中断)${NC}"
fi

echo -n "パターン2 (preStop sleep 15):  "
if [ "$STATUS2" = "200" ]; then
    echo -e "${GREEN}HTTP 200 (正常完了)${NC}"
else
    echo -e "${RED}HTTP $STATUS2 (リクエスト中断)${NC}"
fi

echo ""
echo "期待結果:"
echo "  パターン1: HTTP 000 (接続エラー) ← グレースフルシャットダウンが壊れているため"
echo "  パターン2: HTTP 200 (正常完了)   ← preStop sleep 中にリクエストが完了するため"
echo ""

if [ "$STATUS1" != "200" ] && [ "$STATUS2" = "200" ]; then
    ok "仮説通り: preStop sleep により k8s 環境ではグレースフルシャットダウン問題を回避可能"
elif [ "$STATUS1" = "200" ] && [ "$STATUS2" = "200" ]; then
    warn "両方成功: タイミング的にパターン1でもリクエストが完了した可能性あり（再実行推奨）"
else
    warn "想定外の結果: 詳細な調査が必要"
fi

# ====================
# クリーンアップ
# ====================
echo ""
log "クリーンアップ中..."
cleanup
minikube stop
minikube delete
ok "クリーンアップ完了"
