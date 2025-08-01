package com.idris.log_service.service;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Value;


import org.graylog2.gelfclient.*;
import org.graylog2.gelfclient.transport.GelfTransport;

import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.DisposableBean;
import java.net.InetSocketAddress;
import java.time.Instant;


@Service
public class KafkaLogConsumer implements InitializingBean, DisposableBean {

    private static final Log logger = LogFactory.getLog(KafkaLogConsumer.class);

    @Value("${graylog.host}")
    private String graylogHost;

    @Value("${graylog.port}")
    private int graylogPort;

    @Value("${graylog.protocol}")
    private String graylogProtocol;


    private GelfTransport transport;

    @Override
    public void afterPropertiesSet() {
        try {
            GelfConfiguration config = new GelfConfiguration(new InetSocketAddress(graylogHost, graylogPort))
                    .transport(graylogProtocol.equalsIgnoreCase("TCP") ? GelfTransports.TCP : GelfTransports.UDP)
                    .queueSize(512)
                    .connectTimeout(5000)
                    .reconnectDelay(1000)
                    .tcpNoDelay(true)
                    .sendBufferSize(32768);

            this.transport = GelfTransports.create(config);
            logger.info("GELF transport to Graylog initialized successfully.");
        } catch (Exception e) {
            logger.error("Failed to initialize GELF transport", e);
        }
    }

    @KafkaListener(topics = "logs", groupId = "log-consumers")
    public void consume(
        String logMessage,
        @Header(KafkaHeaders.RECEIVED_PARTITION) int partition
    ) {
        logger.info("Received Kafka message from partition " + partition + ": " + logMessage);

        try {
            GelfMessage gelfMessage = new GelfMessage(logMessage);
            gelfMessage.setLevel(GelfMessageLevel.INFO);
            gelfMessage.setTimestamp(Instant.now().toEpochMilli());
            gelfMessage.setFullMessage(logMessage);
            gelfMessage.addAdditionalField("source", "kafka");
            gelfMessage.addAdditionalField("app", "log-service");

            transport.send(gelfMessage);

        } catch (Exception e) {
            logger.error("Error sending log to Graylog", e);
        }
    }

    @Override
    public void destroy() {
        if (transport != null) {
            transport.stop();
            logger.info("GELF transport to Graylog shut down.");
        }
    }
}
