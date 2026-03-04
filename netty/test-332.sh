#!/bin/bash

cd /workspace
kill -9 $(ss -tlnp | grep 8080 | grep -oP 'pid=\K\d+') 2>/dev/null || true
sleep 2

java -jar target/ktor-graceful-shutdown-1.0-SNAPSHOT.jar > /workspace/logs/shutdown-332.log 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

for i in $(seq 1 30); do
  if curl -s -o /dev/null http://localhost:8080/health 2>/dev/null; then
    echo "Server started after ${i}s"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "ERROR: Server failed to start"
    cat /workspace/logs/shutdown-332.log
    exit 1
  fi
  sleep 1
done

curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/slow > /workspace/logs/curl-result-332.txt 2>/dev/null &
CURL_PID=$!
echo "Curl PID: $CURL_PID, sent /slow request at $(date '+%Y-%m-%d %H:%M:%S.%3N')"

sleep 2
echo "--- SIGTERM sent at $(date '+%Y-%m-%d %H:%M:%S.%3N') ---" >> /workspace/logs/shutdown-332.log
kill -TERM $SERVER_PID
echo "SIGTERM sent to PID $SERVER_PID at $(date '+%Y-%m-%d %H:%M:%S.%3N')"

wait $CURL_PID || true
echo "Curl finished at $(date '+%Y-%m-%d %H:%M:%S.%3N')"
echo "Curl result 3.3.2: $(cat /workspace/logs/curl-result-332.txt)"

wait $SERVER_PID 2>/dev/null || true
echo "Server exited at $(date '+%Y-%m-%d %H:%M:%S.%3N')"
echo "Done with 3.3.2 test"
