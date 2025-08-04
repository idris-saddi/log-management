#!/bin/sh

echo "Waiting for Graylog API..."
until curl -s -u admin:admin http://graylog:9000/api/system/inputs; do
  sleep 3
done

echo "Creating GELF TCP input..."
curl -u admin:admin -X POST http://graylog:9000/api/system/inputs \
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

echo "Creating GELF UDP input..."
curl -u admin:admin -X POST http://graylog:9000/api/system/inputs \
  -H "Content-Type: application/json" \
  -H "X-Requested-By: cli" \
  -d '{
    "title": "GELF UDP",
    "type": "org.graylog2.inputs.gelf.udp.GELFUDPInput",
    "configuration": {
      "bind_address": "0.0.0.0",
      "port": 12202,
      "recv_buffer_size": 1048576
    },
    "global": true,
    "node": null
  }'