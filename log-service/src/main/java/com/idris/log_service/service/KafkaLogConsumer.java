package com.idris.log_service.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.graylog2.gelfclient.*;
import org.graylog2.gelfclient.transport.GelfTransport;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Service;

import java.net.InetSocketAddress;
import java.time.Instant;

@Service
public class KafkaLogConsumer implements InitializingBean, DisposableBean {

    private static final Log logger = LogFactory.getLog(KafkaLogConsumer.class);
    private static final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${graylog.host}")
    private String graylogHost;

    @Value("${graylog.port}")
    private int graylogPort;

    @Value("${graylog.protocol}")
    private String graylogProtocol;

    private GelfTransport transport;

    @Override
    public void afterPropertiesSet() {
        logger.info("🔄 Initializing GELF transport to Graylog at " + graylogHost + ":" + graylogPort + " using " + graylogProtocol);
        try {
            GelfConfiguration config = new GelfConfiguration(new InetSocketAddress(graylogHost, graylogPort))
                    .transport(graylogProtocol.equalsIgnoreCase("TCP") ? GelfTransports.TCP : GelfTransports.UDP)
                    .queueSize(512)
                    .connectTimeout(5000)
                    .reconnectDelay(1000)
                    .tcpNoDelay(true)
                    .sendBufferSize(32768);

            this.transport = GelfTransports.create(config);
            logger.info("✅ GELF transport to Graylog initialized successfully.");
        } catch (Exception e) {
            logger.error("❌ Failed to initialize GELF transport", e);
        }
    }

    @KafkaListener(topics = "logs", groupId = "log-consumers")
    public void consume(String logMessage, @Header(KafkaHeaders.RECEIVED_PARTITION) int partition) {
        logger.info("🔁 Received Kafka message from partition " + partition + ": " + logMessage);

        if (transport == null) {
            logger.warn("⚠️ GELF transport not initialized, skipping log.");
            return;
        }

        try {
            JsonNode json = objectMapper.readTree(logMessage);

            String shortMessage = json.path("message").asText("No message");
            String timestampStr = json.path("timestamp").asText();
            long timestamp = Instant.parse(timestampStr).toEpochMilli();
            String level = json.path("level").asText("INFO");
            String service = json.path("service").asText("unknown");

            GelfMessage gelfMessage = new GelfMessage(shortMessage);
            gelfMessage.setFullMessage(logMessage);
            gelfMessage.setLevel(mapLogLevel(level));
            gelfMessage.setTimestamp(timestamp);
            gelfMessage.addAdditionalField("source", "kafka");
            gelfMessage.addAdditionalField("service", service);

            if (transport.trySend(gelfMessage)) {
                logger.info("✅ Log sent to Graylog successfully.");
            } else {
                logger.warn("⚠️ Failed to send log to Graylog.");
            }

        } catch (Exception e) {
            logger.error("❌ Error sending log to Graylog", e);
        }
    }

    private GelfMessageLevel mapLogLevel(String level) {
        return switch (level.toUpperCase()) {
            case "DEBUG" -> GelfMessageLevel.DEBUG;
            case "INFO" -> GelfMessageLevel.INFO;
            case "WARN" -> GelfMessageLevel.WARNING;
            case "ERROR" -> GelfMessageLevel.ERROR;
            case "FATAL" -> GelfMessageLevel.CRITICAL;
            default -> GelfMessageLevel.INFO;
        };
    }

    @Override
    public void destroy() {
        if (transport != null) {
            transport.stop();
            logger.info("🛑 GELF transport to Graylog shut down.");
        }
    }
}
