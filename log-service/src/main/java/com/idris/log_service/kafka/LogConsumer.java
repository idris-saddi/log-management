package com.idris.log_service.kafka;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.idris.log_service.dto.LogMessage;
import com.idris.log_service.service.LogProcessorService;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class LogConsumer {

    private final LogProcessorService logProcessor;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public LogConsumer(LogProcessorService logProcessor) {
        this.logProcessor = logProcessor;
    }

    @KafkaListener(topics = "logs", groupId = "log-consumers")
    public void consume(ConsumerRecord<String, String> record) {
        try {
            LogMessage logMessage = objectMapper.readValue(record.value(), LogMessage.class);
            logProcessor.process(logMessage);
        } catch (Exception e) {
            System.err.println("❌ Failed to parse or process log: " + e.getMessage());
        }
    }
}
