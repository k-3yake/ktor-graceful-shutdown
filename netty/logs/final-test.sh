#!/bin/bash
PID=$(cat /workspace/logs/final-test-pid.txt)

echo "=== Graceful Shutdown Test (mvn exec:java, NOT fat JAR) ==="
echo "Server PID: $PID"
echo ""

# Start slow request (takes 10s)
echo "$(date '+%H:%M:%S.%3N') - Starting /slow request..."
curl -s -o /workspace/logs/final-body.txt -w "%{http_code}" --max-time 30 http://localhost:8080/slow > /workspace/logs/final-status.txt &
CURL_PID=$!
echo "$(date '+%H:%M:%S.%3N') - Curl PID: $CURL_PID"

# Wait 2 seconds for request to be in-flight
sleep 2

# Send SIGTERM
echo "$(date '+%H:%M:%S.%3N') - Sending SIGTERM to PID $PID..."
kill -TERM "$PID"

# Wait for curl to finish
echo "$(date '+%H:%M:%S.%3N') - Waiting for curl to finish..."
wait $CURL_PID 2>/dev/null
CURL_EXIT=$?
echo "$(date '+%H:%M:%S.%3N') - Curl exit code: $CURL_EXIT"

# Results
HTTP_STATUS=$(cat /workspace/logs/final-status.txt 2>/dev/null)
BODY=$(cat /workspace/logs/final-body.txt 2>/dev/null)
echo ""
echo "=== RESULTS ==="
echo "HTTP Status: [${HTTP_STATUS}]"
echo "Response Body: [${BODY}]"
echo "Curl Exit: $CURL_EXIT"
echo ""

if [ "$HTTP_STATUS" = "200" ]; then
    echo "VERDICT: Graceful shutdown WORKS (request completed with 200)"
elif [ "$HTTP_STATUS" = "000" ] || [ -z "$HTTP_STATUS" ]; then
    echo "VERDICT: Graceful shutdown BROKEN (connection reset, HTTP 000)"
else
    echo "VERDICT: Unexpected status $HTTP_STATUS"
fi

# Wait for server exit
wait $PID 2>/dev/null || true
echo ""
echo "$(date '+%H:%M:%S.%3N') - Server exited"
