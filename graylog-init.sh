#!/bin/sh
#
# Graylog Initialization Script
# =============================
# This script automatically configures Graylog with streams, dashboards, and monitoring
# for multiple microservices in a log management system.
#
# Prerequisites:
# - Graylog server running and accessible
# - Default admin credentials (admin:admin)
# - jq command line JSON processor installed
#
# Author: Idris SADDI
# Version: 1.0
# Date: August 2025
#

# Exit on error and treat unset variables as errors
set -eu pipefail

echo "✅ Bash is working with pipefail!"

#
# Configuration Variables
# =======================
GRAYLOG_URL="http://graylog:9000"           # Graylog server URL
AUTH="admin:admin"                          # Authentication credentials
SERVICES="service1 service2"                # List of services to configure (space-separated)

#
# Wait for Graylog API to be Ready
# ================================
echo "🕒 Waiting for Graylog API..."
until curl -s -u "$AUTH" "$GRAYLOG_URL/api/system/inputs" > /dev/null; do
  sleep 3
done
echo "✅ Graylog API is ready."

#
# Create GELF TCP Input
# ====================
# This creates a GELF (Graylog Extended Log Format) TCP input that will receive
# log messages from applications on port 12201
#
echo "🔌 Creating GELF TCP input..."
GELF_PAYLOAD='{
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

# Send the input creation request to Graylog API
GELF_RESPONSE=$(curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/system/inputs" \
  -H "Content-Type: application/json" \
  -H "X-Requested-By: cli" \
  --data "$GELF_PAYLOAD")

echo "Raw GELF input creation response:"
echo "$GELF_RESPONSE"

# Get default index set ID
DEFAULT_INDEX_SET_ID=$(curl -s -u "$AUTH" "$GRAYLOG_URL/api/system/indices/index_sets" \
  | jq -r '.index_sets[] | select(.default == true) | .id // empty')

if [ -z "$DEFAULT_INDEX_SET_ID" ]; then
  echo "❌ Could not find default index set ID. Exiting..."
  exit 1
fi

echo "📦 Default index set ID: $DEFAULT_INDEX_SET_ID"

#
# Service Configuration Loop
# ===========================
# For each service, create a complete monitoring setup including:
# 1. Stream for filtering logs
# 2. Stream rules for service identification
# 3. Search queries for log analysis
# 4. Dashboard with widgets for visualization
#
for SERVICE in $SERVICES; do
  echo "---"
  echo "🔁 Setting up for $SERVICE"

  #
  # 1. Create Stream
  # ================
  # Streams allow filtering and routing of log messages based on rules
  #
  STREAM_PAYLOAD=$(jq -n \
    --arg title "$SERVICE Stream" \
    --arg description "Stream for $SERVICE" \
    --arg index_set_id "$DEFAULT_INDEX_SET_ID" \
    '{
      "title": $title,
      "description": $description,
      "rules": [],
      "index_set_id": $index_set_id,
      "remove_matches_from_default_stream": false
    }')

  STREAM_RESPONSE=$(curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/streams" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    --data "$STREAM_PAYLOAD")
  echo "Raw stream creation response:"
  echo "$STREAM_RESPONSE"

  # Extract stream ID from response
  STREAM_ID=$(echo "$STREAM_RESPONSE" | jq -r '.id // .stream_id // empty')
  if [ -z "$STREAM_ID" ]; then
    echo "❌ Failed to create stream for $SERVICE."
    continue
  fi
  echo "✅ Created stream for $SERVICE with ID: $STREAM_ID"

  #
  # 2. Add Stream Rule
  # ==================
  # Rules define which messages are routed to this stream
  # Type 1 = exact match rule
  #
  RULE_PAYLOAD=$(jq -n \
    --arg service "$SERVICE" \
    '{
      "field": "service",
      "value": $service,
      "type": 1,
      "inverted": false
    }')
  curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/streams/$STREAM_ID/rules" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    --data "$RULE_PAYLOAD"
  echo "✅ Added rule to stream for $SERVICE"

  #
  # 3. Enable Stream
  # ================
  # Activate the stream to start processing messages
  #
  curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/streams/$STREAM_ID/resume" \
    -H "X-Requested-By: cli"
  echo "✅ Enabled stream for $SERVICE"

  #
  # 4. Create Search Query
  # =====================
  # Search queries enable analysis and monitoring of log data for specific services
  # This creates both total count and error count searches for comprehensive monitoring
  #
  SEARCH_PAYLOAD=$(jq -n \
    --arg stream_id "$STREAM_ID" \
    --arg service "$SERVICE" \
    '{
      "queries": [
        {
          "id": "main_query",
          "query": {
            "type": "elasticsearch",
            "query_string": "service:\($service)"
          },
          "timerange": {
            "type": "relative",
            "range": 300
          },
          "filter": {
            "type": "stream",
            "id": $stream_id
          },
          "search_types": [
            {
              "id": "search-type-count",
              "type": "pivot",
              "query": {
                "type": "elasticsearch",
                "query_string": "service:\($service)"
              },
              "timerange": {
                "type": "relative",
                "range": 300
              },
              "series": [
                {
                  "id": "count()",
                  "type": "count"
                }
              ],
              "rollup": true,
              "sort": []
            },
            {
              "id": "search-type-error-count",
              "type": "pivot",
              "query": {
                "type": "elasticsearch",
                "query_string": "service:\($service) AND level:ERROR"
              },
              "timerange": {
                "type": "relative",
                "range": 300
              },
              "series": [
                {
                  "id": "count()",
                  "type": "count"
                }
              ],
              "rollup": true,
              "sort": []
            }
          ]
        }
      ]
    }')
  
  SEARCH_RESPONSE=$(curl -s -u "$AUTH" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -X POST "$GRAYLOG_URL/api/views/search" \
    --data-raw "$SEARCH_PAYLOAD")
  echo "Raw search creation response:"
  echo "$SEARCH_RESPONSE"

  # Extract search and query IDs from response
  SEARCH_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.id // empty')
  QUERY_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.queries[0].id // empty')
  if [ -z "$SEARCH_ID" ] || [ -z "$QUERY_ID" ]; then
    echo "❌ Failed to create search for $SERVICE."
    exit 1
  fi
  echo "✅ Search created with ID: $SEARCH_ID (query ID: $QUERY_ID)"

  #
  # 5. Create Dashboard
  # ==================
  # Dashboards provide visual interface for monitoring service logs
  # Each dashboard contains widgets displaying metrics and log counts
  #
  DASHBOARD_PAYLOAD=$(jq -n \
    --arg service "$SERVICE" \
    --arg search_id "$SEARCH_ID" \
    '{
      "type": "DASHBOARD",
      "title": "Dashboard for \($service)",
      "summary": "Auto-created dashboard for \($service)",
      "description": "Visualizations for \($service)",
      "search_id": $search_id,
      "state": {},
      "share_request": null,
      "favorite": false
    }')
  
  CREATE_DASHBOARD_RESPONSE=$(curl -s -u "$AUTH" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    -X POST "$GRAYLOG_URL/api/views" \
    --data-raw "$DASHBOARD_PAYLOAD")
  echo "Raw dashboard creation response:"
  echo "$CREATE_DASHBOARD_RESPONSE"

  DASHBOARD_ID=$(echo "$CREATE_DASHBOARD_RESPONSE" | jq -r '.id // empty')
  if [ -z "$DASHBOARD_ID" ]; then
    echo "❌ Failed to create dashboard for $SERVICE."
    exit 1
  fi
  echo "✅ Dashboard created with ID: $DASHBOARD_ID"

  #
  # 6. Add Widgets to Dashboard
  # ===========================
  # Configure dashboard widgets to display:
  # - Total log count (5-minute timeframe)
  # - Error log count (5-minute timeframe)
  #
  NEW_STATE=$(jq -n \
    --arg qid "$QUERY_ID" \
    --arg service "$SERVICE" \
    '{
      ($qid): {
        "selected_fields": [],
        "static_message_list_id": null,
        "titles": {
          "widgets": {
            "widget-1": "Total Logs (5min)",
            "widget-2": "Error Logs (5min)"
          }
        },
        "widgets": [
          {
            "id": "widget-1",
            "type": "aggregation",
            "filter": null,
            "filters": [],
            "config": {
              "visualization": "numeric",
              "row_pivots": [],
              "column_pivots": [],
              "series": [
                {
                  "function": "count()"
                }
              ],
              "sort": [],
              "rollup": true
            }
          },
          {
            "id": "widget-2",
            "type": "aggregation",
            "filter": null,
            "filters": [],
            "config": {
              "visualization": "numeric",
              "row_pivots": [],
              "column_pivots": [],
              "series": [
                {
                  "function": "count()"
                }
              ],
              "sort": [],
              "rollup": true
            }
          }
        ],
        "widget_mapping": {
          "widget-1": ["search-type-count"],
          "widget-2": ["search-type-error-count"]
        },
        "positions": {
          "widget-1": {"col": 1, "row": 1, "height": 1, "width": 1},
          "widget-2": {"col": 2, "row": 1, "height": 1, "width": 1}
        },
        "formatting": {"highlighting": []},
        "display_mode_settings": {"positions": {}}
      }
    }')

  # Merge new widget state with existing dashboard
  EXISTING_VIEW=$(curl -s -u "$AUTH" "$GRAYLOG_URL/api/views/$DASHBOARD_ID")
  MERGED_VIEW=$(echo "$EXISTING_VIEW" | jq --argjson frag "$NEW_STATE" '.state = (.state // {}) * $frag')

  # Update dashboard with widget configuration
  UPDATE_RESPONSE=$(curl -s -u "$AUTH" -X PUT "$GRAYLOG_URL/api/views/$DASHBOARD_ID" \
    -H "Content-Type: application/json" -H "X-Requested-By: cli" \
    --data-raw "$MERGED_VIEW")
  echo "Merged update response:"
  echo "$UPDATE_RESPONSE"

  echo "🎉 $SERVICE setup complete!"
done

echo "🚀 All services successfully configured in Graylog."

  # # 6. Create event definition
  # EVENT_DEF_RESPONSE=$(curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/events/definitions" \
  #   -H "Content-Type: application/json" \
  #   -H "X-Requested-By: cli" \
  #   -d "{
  #     \"title\": \"$SERVICE - ERROR Alert\",
  #     \"description\": \"Alert on ERROR logs for $SERVICE\",
  #     \"priority\": 2,
  #     \"alert\": true,
  #     \"config\": {
  #       \"type\": \"aggregation-v1\",
  #       \"query\": \"service:$SERVICE AND level:ERROR\",
  #       \"series\": [{\"id\": \"count()\", \"function\": \"count()\"}],
  #       \"group_by\": [],
  #       \"search_within_ms\": 60000,
  #       \"execute_every_ms\": 60000
  #     },
  #     \"field_spec\": {},
  #     \"key_spec\": [],
  #     \"notification_settings\": {
  #       \"grace_period_ms\": 60000,
  #       \"backlog_size\": 5
  #     },
  #     \"notifications\": [],
  #     \"storage\": {
  #       \"type\": \"event-definition-default-storage-v1\"
  #     }
  #   }")
  # EVENT_ID=$(echo "$EVENT_DEF_RESPONSE" | jq -r '.id // empty')
  # if [ -z "$EVENT_ID" ]; then
  #   echo "❌ Failed to create event definition for $SERVICE."
  #   echo "$EVENT_DEF_RESPONSE"
  #   continue
  # fi

  # # 7. Create UI notification
  # NOTIF_RESPONSE=$(curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/events/notifications" \
  #   -H "Content-Type: application/json" \
  #   -H "X-Requested-By: cli" \
  #   -d "{
  #     \"title\": \"$SERVICE - UI Notification\",
  #     \"description\": \"In-app notification for $SERVICE errors\",
  #     \"config\": { \"type\": \"notification-v1\" }
  #   }")
  # NOTIF_ID=$(echo "$NOTIF_RESPONSE" | jq -r '.id // empty')
  # if [ -z "$NOTIF_ID" ]; then
  #   echo "❌ Failed to create UI notification for $SERVICE."
  #   echo "$NOTIF_RESPONSE"
  #   continue
  # fi

  # # 8. Link notification to event
  # curl -s -u "$AUTH" -X PUT "$GRAYLOG_URL/api/events/definitions/$EVENT_ID/notifications" \
  #   -H "Content-Type: application/json" \
  #   -H "X-Requested-By: cli" \
  #   -d "[ { \"notification_id\": \"$NOTIF_ID\" } ]"

#   echo "🎉 $SERVICE setup complete!"
# done

# echo "🚀 All services successfully configured in Graylog."
