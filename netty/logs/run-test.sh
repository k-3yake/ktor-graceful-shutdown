#!/bin/bash
set -e

# Kill any existing server
pkill -f "ktor-graceful-shutdown" 2>/dev/null || true
sleep 2

# Start server
java -jar /workspace/target/ktor-graceful-shutdown-1.0-SNAPSHOT.jar > /workspace/logs/shutdown-332-retest.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server to start
for i in $(seq 1 30); do
  if curl -s -o /dev/null http://localhost:8080/health 2>/dev/null; then
    echo "Server started successfully"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "FAILED TO START"
    cat /workspace/logs/shutdown-332-retest.log
    exit 1
  fi
  sleep 1
done

# Send slow request in background
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/slow > /workspace/logs/curl-result-332-retest.txt 2>/dev/null &
CURL_PID=$!
echo "Curl PID: $CURL_PID"

# Wait 2 seconds, then send SIGTERM
sleep 2
echo "Sending SIGTERM at $(date '+%H:%M:%S.%3N')"
kill -TERM $SERVER_PID

# Wait for curl to finish
sleep 25
wait $CURL_PID 2>/dev/null || true
CURL_RESULT=$(cat /workspace/logs/curl-result-332-retest.txt 2>/dev/null)
echo "Curl HTTP status: ${CURL_RESULT:-EMPTY/CONNECTION_RESET}"

wait $SERVER_PID 2>/dev/null || true
echo "Test complete"
