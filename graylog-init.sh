#!/bin/sh

set -eu pipefail

echo "✅ Bash is working with pipefail!"


GRAYLOG_URL="http://graylog:9000"
AUTH="admin:admin"
SERVICES="service-1 service-2"  # Add more service names here

echo "🕒 Waiting for Graylog API..."
until curl -s -u "$AUTH" "$GRAYLOG_URL/api/system/inputs" > /dev/null; do
  sleep 3
done
echo "✅ Graylog API is ready."

# Create GELF TCP input
echo "🔌 Creating GELF TCP input..."
curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/system/inputs" \
  -H "Content-Type: application/json" \
  -H "X-Requested-By: cli" \
  -d '{
    "title": "GELF TCP",
    "type": "org.graylog2.inputs.gelf.tcp.GELFTCPInput",
    "configuration": {
      "bind_address": "0.0.0.0",
      "port": 12201,
      "recv_buffer_size": 1048576,
      "use_tls": false
    },
    "global": true,
    "node": null
  }'

# 📦 Get default index set ID
DEFAULT_INDEX_SET_ID=$(curl -s -u "$AUTH" "$GRAYLOG_URL/api/system/indices/index_sets" \
  | jq -r '.index_sets[] | select(.default == true) | .id')

if [ -z "$DEFAULT_INDEX_SET_ID" ]; then
  echo "❌ Could not find default index set ID. Exiting..."
  exit 1
fi

echo "📦 Default index set ID: $DEFAULT_INDEX_SET_ID"

for SERVICE in $SERVICES; do
  echo "🔁 Setting up for $SERVICE"

  # 1. Create stream
  STREAM_RESPONSE=$(curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/streams" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"title\": \"$SERVICE Stream\",
      \"description\": \"Stream for $SERVICE\",
      \"rules\": [],
      \"index_set_id\": \"$DEFAULT_INDEX_SET_ID\",
      \"remove_matches_from_default_stream\": false
    }")

  # Extract from either 'id' or 'stream_id'
  STREAM_ID=$(echo "$STREAM_RESPONSE" | jq -r '.id // .stream_id // empty')

  if [ -z "$STREAM_ID" ]; then
    echo "❌ Failed to create stream for $SERVICE. Response:"
    echo "$STREAM_RESPONSE"
    continue
  fi

  echo "✅ Created stream for $SERVICE with ID: $STREAM_ID"

  # 2. Add rule to stream
  curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/streams/$STREAM_ID/rules" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"field\": \"service\",
      \"value\": \"$SERVICE\",
      \"type\": 1,
      \"inverted\": false
    }"

  echo "✅ Added rule to stream for $SERVICE"

  # 3. Enable stream
  curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/streams/$STREAM_ID/resume" \
    -H "X-Requested-By: cli"

  echo "✅ Enabled stream for $SERVICE"

  # 4. Create Dashboard (View)
  
  # Clean service name
  CLEAN_SERVICE=$(echo "$SERVICE" | tr -d '\000-\037' | sed 's/[^[:print:]]//g')

  DASHBOARD_PAYLOAD=$(jq -n \
    --arg title "$CLEAN_SERVICE Dashboard" \
    --arg summary "Dashboard for $CLEAN_SERVICE" \
    '{
      "title": $title,
      "summary": $summary,
      "type": "DASHBOARD",
    }'
  ) || { echo "❌ Failed to build JSON payload for dashboard"; exit 1; }

  # POST safely and capture response
  DASHBOARD_RESPONSE=$(echo "$DASHBOARD_PAYLOAD" | curl -s -u "$AUTH" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -X POST "$GRAYLOG_URL/api/views" \
    -d @-)

  echo "Dashboard creation response:"
  echo "$DASHBOARD_RESPONSE"

  DASHBOARD_ID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.id // empty')

  if [ -z "$DASHBOARD_ID" ]; then
    echo "❌ Failed to create dashboard for $CLEAN_SERVICE"
    exit 1
  else
    echo "✅ Created dashboard for $CLEAN_SERVICE with ID: $DASHBOARD_ID"
  fi




  # Widget a: Total logs (5min)
  echo "📊 Adding widgets to $SERVICE Dashboard..."

  curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/dashboards/$DASHBOARD_ID/widgets" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"description\": \"Total Logs (5min)\",
      \"type\": \"SEARCH_RESULT_COUNT\",
      \"cache_time\": 10,
      \"config\": {
        \"query\": \"service:$SERVICE\",
        \"timerange\": { \"type\": \"relative\", \"range\": 300 }
      },
      \"col\": 0,
      \"row\": 0
    }"

  # Widget b: Error logs
  curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/dashboards/$DASHBOARD_ID/widgets" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"description\": \"Error Logs (5min)\",
      \"type\": \"SEARCH_RESULT_COUNT\",
      \"cache_time\": 10,
      \"config\": {
        \"query\": \"service:$SERVICE AND level:ERROR\",
        \"timerange\": { \"type\": \"relative\", \"range\": 300 }
      },
      \"col\": 1,
      \"row\": 0
    }"

  # Widget c: Log volume over time
  curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/dashboards/$DASHBOARD_ID/widgets" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"description\": \"Log Volume Over Time (10min)\",
      \"type\": \"HISTOGRAM\",
      \"cache_time\": 10,
      \"config\": {
        \"query\": \"service:$SERVICE\",
        \"timerange\": { \"type\": \"relative\", \"range\": 600 },
        \"interval\": \"minute\"
      },
      \"col\": 0,
      \"row\": 1
    }"

  # Widget d: Level breakdown
  curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/dashboards/$DASHBOARD_ID/widgets" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"description\": \"Log Levels Breakdown\",
      \"type\": \"QUICKVALUES\",
      \"cache_time\": 10,
      \"config\": {
        \"field\": \"level\",
        \"query\": \"service:$SERVICE\",
        \"timerange\": { \"type\": \"relative\", \"range\": 300 }
      },
      \"col\": 1,
      \"row\": 1
    }"

  # Widget e: Latest logs table
  curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/dashboards/$DASHBOARD_ID/widgets" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"description\": \"Latest Logs\",
      \"type\": \"MESSAGE_TABLE\",
      \"cache_time\": 10,
      \"config\": {
        \"query\": \"service:$SERVICE\",
        \"fields\": [\"timestamp\", \"level\", \"message\", \"user_id\"],
        \"limit\": 20,
        \"sort\": [{\"field\": \"timestamp\", \"order\": \"desc\"}],
        \"timerange\": { \"type\": \"relative\", \"range\": 300 }
      },
      \"col\": 0,
      \"row\": 2
    }"

  # 6. Create event definition
  EVENT_DEF_RESPONSE=$(curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/events/definitions" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"title\": \"$SERVICE - ERROR Alert\",
      \"description\": \"Alert on ERROR logs for $SERVICE\",
      \"priority\": 2,
      \"alert\": true,
      \"config\": {
        \"type\": \"aggregation-v1\",
        \"query\": \"service:$SERVICE AND level:ERROR\",
        \"series\": [{\"id\": \"count()\", \"function\": \"count()\"}],
        \"group_by\": [],
        \"search_within_ms\": 60000,
        \"execute_every_ms\": 60000
      },
      \"field_spec\": {},
      \"key_spec\": [],
      \"notification_settings\": {
        \"grace_period_ms\": 60000,
        \"backlog_size\": 5
      },
      \"notifications\": [],
      \"storage\": {
        \"type\": \"event-definition-default-storage-v1\"
      }
    }")
  EVENT_ID=$(echo "$EVENT_DEF_RESPONSE" | jq -r '.id // empty')
  if [ -z "$EVENT_ID" ]; then
    echo "❌ Failed to create event definition for $SERVICE."
    echo "$EVENT_DEF_RESPONSE"
    continue
  fi

  # 7. Create UI notification
  NOTIF_RESPONSE=$(curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/events/notifications" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "{
      \"title\": \"$SERVICE - UI Notification\",
      \"description\": \"In-app notification for $SERVICE errors\",
      \"config\": { \"type\": \"notification-v1\" }
    }")
  NOTIF_ID=$(echo "$NOTIF_RESPONSE" | jq -r '.id // empty')
  if [ -z "$NOTIF_ID" ]; then
    echo "❌ Failed to create UI notification for $SERVICE."
    echo "$NOTIF_RESPONSE"
    continue
  fi

  # 8. Link notification to event
  curl -s -u "$AUTH" -X PUT "$GRAYLOG_URL/api/events/definitions/$EVENT_ID/notifications" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -d "[ { \"notification_id\": \"$NOTIF_ID\" } ]"

  echo "🎉 $SERVICE setup complete!"
done

echo "🚀 All services successfully configured in Graylog."
