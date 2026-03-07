#!/bin/bash
# 共通関数ライブラリ

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
ok()  { echo -e "${GREEN}[OK]${NC} $*"; }
ng()  { echo -e "${RED}[NG]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOGS_DIR"

wait_for_pod_ready() {
    log "Podがreadyになるのを待機中..."
    local retries=0
    while true; do
        local ready_count
        ready_count=$(kubectl get pods -l app=ktor-app --field-selector=status.phase=Running \
            -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
            | grep -c "True" || echo "0")
        if [ "$ready_count" -ge 1 ]; then
            ok "Podがreadyになりました (ready=$ready_count)"
            return
        fi
        retries=$((retries + 1))
        if [ $retries -ge 24 ]; then
            ng "Podがreadyになりませんでした"
            kubectl get pods -l app=ktor-app
            return 1
        fi
        log "リトライ中... ($retries)"
        sleep 5
    done
}

get_service_url() {
    minikube service ktor-app --url 2>/dev/null | head -1
}

run_test() {
    local pattern_name="$1"
    local log_file="$2"
    local url
    url=$(get_service_url)
    log "Service URL: $url" >&2

    # テスト対象のPod名を記録（Running状態のもの）
    local target_pod
    target_pod=$(kubectl get pods -l app=ktor-app --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}')
    log "対象Pod: $target_pod" >&2

    # ヘルスチェック（リトライあり）
    local health_status
    local health_retries=0
    while true; do
        health_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url/health" 2>/dev/null || echo "000")
        if [ "$health_status" = "200" ]; then
            break
        fi
        health_retries=$((health_retries + 1))
        if [ $health_retries -ge 5 ]; then
            ng "ヘルスチェック失敗 (HTTP $health_status)" >&2
            echo "000"
            return
        fi
        log "ヘルスチェック リトライ中... ($health_retries/5)" >&2
        sleep 2
    done
    ok "ヘルスチェック成功" >&2

    # /slow にリクエスト送信（バックグラウンド）
    local request_time
    request_time=$(date --utc '+%H:%M:%S.%3N')
    log "/slow にリクエスト送信中（30秒かかる処理）..." >&2
    local tmpfile
    tmpfile=$(mktemp)
    curl -s -o /dev/null -w "%{http_code}" --max-time 60 "$url/slow" > "$tmpfile" 2>/dev/null &
    local curl_pid=$!

    # 2秒待ってから rollout restart
    sleep 2
    local restart_time
    restart_time=$(date --utc '+%H:%M:%S.%3N')
    log "kubectl rollout restart 実行..." >&2
    kubectl rollout restart deployment/ktor-app >&2

    # curl の完了を待つ
    log "リクエスト完了を待機中..." >&2
    wait $curl_pid || true
    local response_time
    response_time=$(date --utc '+%H:%M:%S.%3N')
    local http_status
    http_status=$(cat "$tmpfile")
    rm -f "$tmpfile"

    # ログを先に取得（Pod削除前に確保）
    log "Podログを収集中..." >&2
    sleep 1
    kubectl logs "$target_pod" --timestamps=true > "$log_file" 2>/dev/null || true

    # コンテナが terminated になるまでポーリングしてPod状態を記録
    log "コンテナ終了を待機中..." >&2
    local wait_count=0
    while true; do
        if ! kubectl get pod "$target_pod" -o json > "$log_file.pod.json" 2>/dev/null; then
            echo '{"_deleted": true}' > "$log_file.pod.json"
            break
        fi
        local phase
        phase=$(jq -r '.status.containerStatuses[0].state | keys[0]' "$log_file.pod.json" 2>/dev/null || echo "unknown")
        if [ "$phase" = "terminated" ]; then
            break
        fi
        wait_count=$((wait_count + 1))
        if [ $wait_count -ge 30 ]; then
            warn "コンテナ終了待ちタイムアウト" >&2
            break
        fi
        sleep 2
    done

    # k8sイベントを取得
    log "k8sイベントを取得中..." >&2
    local events_raw
    events_raw=$(kubectl get events --field-selector "involvedObject.name=$target_pod" \
        --sort-by='.lastTimestamp' -o json 2>/dev/null || echo '{"items":[]}')

    # クライアント側タイムラインとPod状態をログファイルに追記
    {
        echo "--- client timeline ---"
        echo "$request_time [CLIENT] curl /slow 送信"
        echo "$restart_time [CLIENT] kubectl rollout restart 実行"
        echo "$response_time [CLIENT] curl 完了 HTTP ${http_status:-000}"
        echo "--- pod status ---"
        if jq -e '._deleted' "$log_file.pod.json" > /dev/null 2>&1; then
            echo "pod: 既に削除済み（terminated → deleted）"
        else
            local started_at finished_at deletion_ts exit_code reason
            started_at=$(jq -r '.status.containerStatuses[0].state.terminated.startedAt // .status.containerStatuses[0].state.running.startedAt // "N/A"' "$log_file.pod.json" 2>/dev/null)
            finished_at=$(jq -r '.status.containerStatuses[0].state.terminated.finishedAt // "still running"' "$log_file.pod.json" 2>/dev/null)
            exit_code=$(jq -r '.status.containerStatuses[0].state.terminated.exitCode // "N/A"' "$log_file.pod.json" 2>/dev/null)
            reason=$(jq -r '.status.containerStatuses[0].state.terminated.reason // "N/A"' "$log_file.pod.json" 2>/dev/null)
            deletion_ts=$(jq -r '.metadata.deletionTimestamp // "N/A"' "$log_file.pod.json" 2>/dev/null)
            echo "container startedAt:  $started_at"
            echo "container finishedAt: $finished_at"
            echo "container exitCode:   $exit_code"
            echo "container reason:     $reason"
            echo "pod deletionTimestamp: $deletion_ts"
        fi
        echo "--- k8s events ---"
        echo "$events_raw" | jq -r '.items[] | "\(.lastTimestamp) \(.reason) \(.message)"' 2>/dev/null || echo "(イベント取得失敗)"
    } >> "$log_file"

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

print_timeline() {
    local label="$1"
    local log_file="$2"

    echo ""
    echo -e "${YELLOW}=== $label タイムライン ===${NC}"
    echo ""

    if [ -f "$log_file" ]; then
        # k8sタイムスタンプ付きログからEVENT行を抽出
        { grep '\[EVENT\]' "$log_file" || true; } | while IFS= read -r line; do
            local ts
            ts=$(echo "$line" | grep -oP '^\S+' | grep -oP '\d{2}:\d{2}:\d{2}\.\d{3}')
            local event
            event=$(echo "$line" | grep -oP '\[EVENT\].*')
            if [ -n "$ts" ] && [ -n "$event" ]; then
                printf "  %s  %s\n" "$ts" "$event"
            fi
        done

        # クライアント側タイムライン
        echo ""
        { grep '^\[CLIENT\]\|^\S\+\s\[CLIENT\]' "$log_file" 2>/dev/null || true; } | while IFS= read -r line; do
            local ts event
            ts=$(echo "$line" | awk '{print $1}')
            event=$(echo "$line" | sed 's/^[^ ]* //')
            printf "  %s  %s\n" "$ts" "$event"
        done

        # k8sイベント（Killingなど重要イベント）
        echo ""
        local events_section=false
        while IFS= read -r line; do
            if [[ "$line" == "--- k8s events ---" ]]; then
                events_section=true
                continue
            fi
            if [[ "$line" == "---"* ]] && $events_section; then
                break
            fi
            if $events_section && echo "$line" | grep -q 'Killing'; then
                local ev_ts ev_rest
                ev_ts=$(echo "$line" | awk '{print $1}' | grep -oP '\d{2}:\d{2}:\d{2}' || true)
                ev_rest=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')
                if [ -n "$ev_ts" ]; then
                    printf "  %s      [K8S] %s\n" "$ev_ts" "$ev_rest"
                fi
            fi
        done < "$log_file"

        # Pod状態
        echo ""
        { grep -A1 'container \(startedAt\|finishedAt\)\|pod deletionTimestamp' "$log_file" 2>/dev/null || true; } | while IFS= read -r line; do
            if [ -n "$line" ]; then
                printf "  %s\n" "$line"
            fi
        done
    fi
    echo ""
}

check_setup() {
    if ! minikube status 2>/dev/null | grep -q "Running"; then
        ng "minikubeが起動していません。先に ./setup.sh を実行してください。"
        exit 1
    fi
    if ! kubectl get service ktor-app &>/dev/null; then
        ng "Service ktor-app が存在しません。先に ./setup.sh を実行してください。"
        exit 1
    fi
    ok "セットアップ確認OK"
}
