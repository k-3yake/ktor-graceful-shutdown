#!/bin/bash
set -euo pipefail

PORT=8080
JAR="target/ktor-graceful-shutdown-1.0-SNAPSHOT.jar"
APP_PID=""

cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -9 "$APP_PID" 2>/dev/null
    wait "$APP_PID" 2>/dev/null
  fi
}
trap cleanup EXIT

echo "=== グレースフルシャットダウン検証 ==="

# ビルド
if [ ! -f "$JAR" ]; then
  echo "[0] ビルド中..."
  ./mvnw -q package -DskipTests
fi

# サーバー起動 (java -jar で直接起動)
echo "[1] サーバーを起動します..."
java -jar "$JAR" &
APP_PID=$!

# サーバーが起動するまで待機
echo "[2] サーバーの起動を待機中..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null http://localhost:${PORT}/health 2>/dev/null; then
    echo "    サーバーが起動しました (PID: $APP_PID)"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "    サーバーの起動がタイムアウトしました"
    exit 1
  fi
  sleep 1
done

# /slow エンドポイントにリクエスト送信 (バックグラウンド)
echo "[3] /slow にリクエストを送信します（10秒かかる処理）..."
CURL_RESULT=$(mktemp)
curl -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/slow > "$CURL_RESULT" 2>/dev/null &
CURL_PID=$!

# リクエストが処理され始めるまで少し待つ
sleep 2

# SIGTERM でシャットダウン
echo "[4] サーバーに SIGTERM を送信します (PID: $APP_PID)..."
kill -TERM "$APP_PID"

# curl の結果を待つ
echo "[5] リクエストの結果を確認中..."
CURL_EXIT=0
wait "$CURL_PID" || CURL_EXIT=$?
RESPONSE=$(cat "$CURL_RESULT")
rm -f "$CURL_RESULT"

wait "$APP_PID" 2>/dev/null || true
APP_PID=""

echo ""
echo "=== 結果 ==="
echo "curl 終了コード: $CURL_EXIT"
echo "HTTPステータス: ${RESPONSE:-なし}"

if [ "$CURL_EXIT" -ne 0 ] || [ -z "$RESPONSE" ] || [ "$RESPONSE" != "200" ]; then
  echo ""
  echo "=> リクエストが中断されました。グレースフルシャットダウンが出来ていません。"
else
  echo ""
  echo "=> リクエストは正常に完了しました。グレースフルシャットダウンが出来ています。"
fi
