#!/bin/bash
set -e

MVN_PID=$(cat /workspace/logs/mvn_pid2.txt)
echo "Maven/Java PID: $MVN_PID"

# Start slow request in background
echo "$(date '+%H:%M:%S.%3N') - Starting /slow request (takes 10s)..."
curl -s -o /workspace/logs/curl-body.txt -w "%{http_code}" http://localhost:8080/slow > /workspace/logs/curl-status.txt 2>/dev/null &
CURL_PID=$!
echo "Curl PID: $CURL_PID"

# Wait 2 seconds so the request is in-flight
sleep 2

# Send SIGTERM
echo "$(date '+%H:%M:%S.%3N') - Sending SIGTERM to PID $MVN_PID"
kill -TERM $MVN_PID 2>/dev/null || true

# Wait for curl to finish (give it up to 30s)
echo "$(date '+%H:%M:%S.%3N') - Waiting for curl to finish..."
wait $CURL_PID 2>/dev/null
CURL_EXIT=$?
echo "$(date '+%H:%M:%S.%3N') - Curl finished with exit code: $CURL_EXIT"

HTTP_STATUS=$(cat /workspace/logs/curl-status.txt 2>/dev/null || echo "EMPTY")
BODY=$(cat /workspace/logs/curl-body.txt 2>/dev/null || echo "EMPTY")
echo "HTTP Status: $HTTP_STATUS"
echo "Response Body: $BODY"

# Wait for server to fully exit
wait $MVN_PID 2>/dev/null || true
echo "$(date '+%H:%M:%S.%3N') - Server process exited"
