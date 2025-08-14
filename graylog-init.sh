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
    exit 1
  else
    echo "✅ Created stream for $SERVICE with ID: $STREAM_ID"
  fi

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
  # This creates comprehensive monitoring with multiple search types:
  # - Total log count, Error count, Warning count, Log levels distribution
  # - Log timeline chart, Response time analysis, Top log sources
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
            },
            {
              "id": "search-type-warning-count",
              "type": "pivot",
              "query": {
                "type": "elasticsearch",
                "query_string": "service:\($service) AND level:WARN"
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
              "id": "search-type-level-distribution",
              "type": "pivot",
              "query": {
                "type": "elasticsearch",
                "query_string": "service:\($service)"
              },
              "timerange": {
                "type": "relative",
                "range": 300
              },
              "row_groups": [
                {
                  "field": "level",
                  "type": "values",
                  "limit": 10
                }
              ],
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
              "id": "search-type-timeline",
              "type": "pivot",
              "query": {
                "type": "elasticsearch",
                "query_string": "service:\($service)"
              },
              "timerange": {
                "type": "relative",
                "range": 300
              },
              "row_groups": [
                {
                  "field": "timestamp",
                  "type": "time",
                  "interval": {
                    "type": "timeunit",
                    "timeunit": "1m"
                  }
                }
              ],
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
              "id": "search-type-response-times",
              "type": "pivot",
              "query": {
                "type": "elasticsearch",
                "query_string": "service:\($service) AND response_time:*"
              },
              "timerange": {
                "type": "relative",
                "range": 300
              },
              "series": [
                {
                  "id": "avg(response_time)",
                  "type": "avg",
                  "field": "response_time"
                },
                {
                  "id": "max(response_time)",
                  "type": "max",
                  "field": "response_time"
                }
              ],
              "rollup": true,
              "sort": []
            },
            {
              "id": "search-type-top-sources",
              "type": "pivot",
              "query": {
                "type": "elasticsearch",
                "query_string": "service:\($service)"
              },
              "timerange": {
                "type": "relative",
                "range": 300
              },
              "row_groups": [
                {
                  "field": "source",
                  "type": "values",
                  "limit": 5
                }
              ],
              "series": [
                {
                  "id": "count()",
                  "type": "count"
                }
              ],
              "rollup": true,
              "sort": [
                {
                  "type": "pivot",
                  "field": "count()",
                  "direction": "Descending"
                }
              ]
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
  
  # Check if search creation was successful
  if echo "$SEARCH_RESPONSE" | grep -q '"id"'; then
    echo "✅ Search queries created successfully"
  else
    echo "❌ Search creation failed:"
    echo "$SEARCH_RESPONSE"
    exit 1
  fi

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

  if echo "$CREATE_DASHBOARD_RESPONSE" | grep -q '"id"'; then
    DASHBOARD_ID=$(echo "$CREATE_DASHBOARD_RESPONSE" | jq -r '.id // empty')
    echo "✅ Dashboard created successfully"
  else
    echo "❌ Dashboard creation failed:"
    echo "$CREATE_DASHBOARD_RESPONSE"
    exit 1
  fi

  #
  # 6. Add Widgets to Dashboard
  # ===========================
  # Configure dashboard widgets with comprehensive monitoring visualization:
  # - Total log count, Error count, Warning count (numeric widgets)
  # - Log levels distribution (pie chart)
  # - Log timeline (line chart)
  # - Response time metrics (bar chart)
  # - Top log sources (table)
  # Using a larger 4x4 grid layout for better visibility
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
            "widget-1": "📊 Total Logs (5min)",
            "widget-2": "🚨 Error Logs (5min)",
            "widget-3": "⚠️ Warning Logs (5min)",
            "widget-4": "📈 Log Levels Distribution",
            "widget-5": "⏱️ Log Timeline",
            "widget-6": "🚀 Response Time Metrics",
            "widget-7": "🔍 Top Log Sources"
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
          },
          {
            "id": "widget-3",
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
            "id": "widget-4",
            "type": "aggregation",
            "filter": null,
            "filters": [],
            "config": {
              "visualization": "pie",
              "row_pivots": [
                {
                  "field": "level",
                  "type": "values",
                  "config": {
                    "limit": 10
                  }
                }
              ],
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
            "id": "widget-5",
            "type": "aggregation",
            "filter": null,
            "filters": [],
            "config": {
              "visualization": "line",
              "row_pivots": [
                {
                  "field": "timestamp",
                  "type": "time",
                  "config": {
                    "interval": {
                      "type": "timeunit",
                      "unit": "minutes",
                      "value": 1
                    }
                  }
                }
              ],
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
            "id": "widget-6",
            "type": "aggregation",
            "filter": null,
            "filters": [],
            "config": {
              "visualization": "bar",
              "row_pivots": [],
              "column_pivots": [],
              "series": [
                {
                  "function": "avg(response_time)"
                },
                {
                  "function": "max(response_time)"
                }
              ],
              "sort": [],
              "rollup": true
            }
          },
          {
            "id": "widget-7",
            "type": "aggregation",
            "filter": null,
            "filters": [],
            "config": {
              "visualization": "table",
              "row_pivots": [
                {
                  "field": "source",
                  "type": "values",
                  "config": {
                    "limit": 5
                  }
                }
              ],
              "column_pivots": [],
              "series": [
                {
                  "function": "count()"
                }
              ],
              "sort": [
                {
                  "type": "pivot",
                  "field": "count()",
                  "direction": "Descending"
                }
              ],
              "rollup": true
            }
          }
        ],
        "widget_mapping": {
          "widget-1": ["search-type-count"],
          "widget-2": ["search-type-error-count"],
          "widget-3": ["search-type-warning-count"],
          "widget-4": ["search-type-level-distribution"],
          "widget-5": ["search-type-timeline"],
          "widget-6": ["search-type-response-times"],
          "widget-7": ["search-type-top-sources"]
        },
        "positions": {
          "widget-1": {"col": 1, "row": 1, "height": 2, "width": 2},
          "widget-2": {"col": 3, "row": 1, "height": 2, "width": 2},
          "widget-3": {"col": 5, "row": 1, "height": 2, "width": 2},
          "widget-4": {"col": 1, "row": 3, "height": 3, "width": 3},
          "widget-5": {"col": 4, "row": 3, "height": 3, "width": 4},
          "widget-6": {"col": 1, "row": 6, "height": 2, "width": 3},
          "widget-7": {"col": 4, "row": 6, "height": 2, "width": 4}
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
  
  # Check if dashboard update was successful
  if echo "$UPDATE_RESPONSE" | grep -q '"id"'; then
    echo "✅ Dashboard widgets configured successfully"
  else
    echo "❌ Dashboard update failed:"
    echo "$UPDATE_RESPONSE"
    exit 1
  fi

  #
  # 7. Create Event Definition for Error Monitoring
  # ===============================================
  # Event definitions trigger alerts when specific conditions are met
  # This creates an alert that fires when ERROR logs are detected for the service
  #
  echo "🚨 Creating error alert event definition for $SERVICE..."
  EVENT_DEF_PAYLOAD=$(jq -n \
    --arg service "$SERVICE" \
  --arg stream_id "$STREAM_ID" \
    '{
      "title": "\($service) - ERROR Alert",
      "description": "Alert triggered when ERROR logs are detected for \($service)",
      "priority": 2,
      "alert": true,
      "config": {
        "type": "aggregation-v1",
    "query": "service:\($service) AND (level:ERROR OR level:3)",
    "streams": ["\($stream_id)"],
        "group_by": [],
        "series": [
          {
            "id": "count()",
            "type": "count"
          }
        ],
        "conditions": {
          "expression": {
            "expr": ">",
            "left": {
              "expr": "number-ref",
              "ref": "count()"
            },
            "right": {
              "expr": "number",
              "value": 0
            }
          }
        },
        "search_within_ms": 60000,
        "execute_every_ms": 60000
      },
      "field_spec": {},
      "key_spec": [],
      "notification_settings": {
        "grace_period_ms": 60000,
        "backlog_size": 5
      },
      "notifications": []
    }')

  EVENT_DEF_RESPONSE=$(curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/events/definitions" \
    -H "Content-Type: application/json" \
    -H "X-Requested-By: cli" \
    --data-raw "$EVENT_DEF_PAYLOAD")
  if [ -z "$EVENT_DEF_RESPONSE" ]; then
    echo "❌ Failed to create event definition for $SERVICE."
    exit 1
  fi


  EVENT_ID=$(echo "$EVENT_DEF_RESPONSE" | jq -r '.id // empty')
  if [ -z "$EVENT_ID" ]; then
    echo "❌ Failed to create event definition for $SERVICE."
    echo "Error details: $EVENT_DEF_RESPONSE"
    exit 1
  else
    echo "✅ Created event definition for $SERVICE with ID: $EVENT_ID"
  SERIES_TYPE_RETURNED=$(echo "$EVENT_DEF_RESPONSE" | jq -r '.config.series[0].type // empty') || true
    if [ -z "$SERIES_TYPE_RETURNED" ] || [ "$SERIES_TYPE_RETURNED" = "null" ]; then
      echo "🔧 Patching event definition to add missing series type..."
      EVENT_DEF_CURRENT=$(curl -s -u "$AUTH" "$GRAYLOG_URL/api/events/definitions/$EVENT_ID")
      if echo "$EVENT_DEF_CURRENT" | grep -q '"id"'; then
  EVENT_DEF_PATCHED=$(echo "$EVENT_DEF_CURRENT" | jq '.config.series = [ { "id":"count()", "type":"count" } ]')
        PATCH_RESP=$(curl -s -u "$AUTH" -X PUT "$GRAYLOG_URL/api/events/definitions/$EVENT_ID" \
          -H "Content-Type: application/json" -H "X-Requested-By: cli" \
          --data-raw "$EVENT_DEF_PATCHED")
        if echo "$PATCH_RESP" | grep -q '"series"'; then
          echo "✅ Series type patched"
        else
          echo "⚠️ Failed to patch series type: $PATCH_RESP"
        fi
      else
        echo "⚠️ Could not retrieve event definition for series patch"
      fi
    fi

    # Enable the event definition (set state = ENABLED)
    EVENT_DEF_GET=$(curl -s -u "$AUTH" "$GRAYLOG_URL/api/events/definitions/$EVENT_ID")
    if echo "$EVENT_DEF_GET" | grep -q '"id"'; then
      EVENT_DEF_ENABLED=$(echo "$EVENT_DEF_GET" | jq '.state = "ENABLED"')
      ENABLE_EVENT_RESPONSE=$(curl -s -u "$AUTH" -X PUT "$GRAYLOG_URL/api/events/definitions/$EVENT_ID" \
        -H "Content-Type: application/json" -H "X-Requested-By: cli" \
        --data-raw "$EVENT_DEF_ENABLED")
      if echo "$ENABLE_EVENT_RESPONSE" | grep -qi 'RequestError'; then
        echo "⚠️ Failed to enable event definition (may already be enabled): $ENABLE_EVENT_RESPONSE"
      else
        echo "✅ Event definition enabled"
  echo "ℹ️ Event scoped to stream $STREAM_ID for $SERVICE"
      fi
    else
      echo "⚠️ Could not retrieve event definition for enabling: $EVENT_DEF_GET"
    fi

    #
    # 8. Create UI Notification
    # =========================
    # Notifications define how alerts are delivered to users
    # This creates an in-app notification for the error alerts
    #
    echo "📢 Creating HTTP notification for $SERVICE (fires webhook)..."

    # Webhook endpoint (override by setting GRAYLOG_WEBHOOK_URL env before running script)
    WEBHOOK_URL=${GRAYLOG_WEBHOOK_URL:-"http://example.com/graylog-webhook"}
    BODY_TEMPLATE='{"service":"${event_definition_title}","event_id":"${event.id}","message":"${event.message}"}'

    NOTIF_PAYLOAD=$(jq -n \
      --arg service "$SERVICE" \
      --arg url "$WEBHOOK_URL" \
      --arg body "$BODY_TEMPLATE" \
      '{
        title: ($service + " - HTTP Notification"),
        description: ("Webhook notification for " + $service + " error alerts"),
        config: {
          type: "http-notification-v1",
          url: $url,
          api_key_as_header: false,
          skip_tls_verification: true
        }
      }')

    NOTIF_RESPONSE=$(curl -s -u "$AUTH" -X POST "$GRAYLOG_URL/api/events/notifications" \
      -H "Content-Type: application/json" \
      -H "X-Requested-By: cli" \
      --data-raw "$NOTIF_PAYLOAD")
    if echo "$NOTIF_RESPONSE" | grep -q '"id"'; then
      echo "✅ Notification created"
    else
      echo "❌ Notification creation failed: $NOTIF_RESPONSE"
      exit 1
    fi

    NOTIF_ID=$(echo "$NOTIF_RESPONSE" | jq -r '.id // empty')
    if [ -z "$NOTIF_ID" ]; then
      echo "❌ Skipping linking due to notification creation failure."
    else
      echo "✅ Created notification for $SERVICE with ID: $NOTIF_ID"

      #
      # 9. Link Notification to Event Definition
      # =========================================
      # Connect the notification to the event definition so alerts are sent
      # when the event conditions are triggered
      #
      echo "🔗 Attaching notification to event definition for $SERVICE (updating event definition)..."
      CURRENT_EVENT_DEF=$(curl -s -u "$AUTH" "$GRAYLOG_URL/api/events/definitions/$EVENT_ID")
      if echo "$CURRENT_EVENT_DEF" | grep -q '"id"'; then
        UPDATED_EVENT_DEF=$(echo "$CURRENT_EVENT_DEF" | jq --arg nid "$NOTIF_ID" '.notifications = [ { "notification_id": $nid } ]')
        UPDATE_NOTIF_RESPONSE=$(curl -s -u "$AUTH" -X PUT "$GRAYLOG_URL/api/events/definitions/$EVENT_ID" \
          -H "Content-Type: application/json" -H "X-Requested-By: cli" \
          --data-raw "$UPDATED_EVENT_DEF")
        if echo "$UPDATE_NOTIF_RESPONSE" | grep -q '"notifications"'; then
          echo "✅ Notification attached to event definition"
        else
          echo "⚠️ Failed to attach notification: $UPDATE_NOTIF_RESPONSE"
        fi
      else
        echo "❌ Could not retrieve event definition for notification attachment: $CURRENT_EVENT_DEF"
      fi
    fi
    
  fi

  echo "🎉 $SERVICE setup complete!"
done

echo "🚀 All services successfully configured in Graylog."
