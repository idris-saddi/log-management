package com.idris.service2;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/log")
public class LogController {

    private final KafkaTemplate<String, String> kafkaTemplate;

    public LogController(KafkaTemplate<String, String> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    @Value("${spring.application.name}")
    private String applicationName;

    @PostMapping
    public ResponseEntity<?> postLog(
        @RequestParam(defaultValue = "Test log message") String message,
        @RequestParam(required = false, defaultValue = "INFO") String level
    ) {
        try {
            Map<String, Object> log = new HashMap<>();
            log.put("timestamp", java.time.Instant.now().toString());
            log.put("message", message);
            log.put("level", normalizeLevel(level));
            log.put("service", applicationName);

            String logJson = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(log);
            kafkaTemplate.send("logs", logJson);
            return ResponseEntity.ok("Log sent to Kafka: " + logJson);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body("Failed to send log: " + e.getMessage());
        }
    }

    @GetMapping
    public ResponseEntity<?> getLog(
        @RequestParam(defaultValue = "Test log message") String message,
        @RequestParam(required = false, defaultValue = "INFO") String level
    ) {
        try {
            Map<String, Object> log = new HashMap<>();
            log.put("timestamp", java.time.Instant.now().toString());
            log.put("message", message);
            log.put("level", normalizeLevel(level));
            log.put("service", applicationName);

            String logJson = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(log);
            kafkaTemplate.send("logs", logJson);
            return ResponseEntity.ok("Log sent to Kafka: " + logJson);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body("Failed to send log: " + e.getMessage());
        }
    }

    private String normalizeLevel(String level) {
        if (level == null)
            return "INFO";
        String upper = level.trim().toUpperCase();
        switch (upper) {
            case "ERROR":
                return "ERROR";
            case "WARN":
            case "WARNING":
                return "WARN";
            case "DEBUG":
            case "TRACE":
            case "INFO":
                return upper;
            default:
                return "INFO"; // fallback
        }
    }
}
