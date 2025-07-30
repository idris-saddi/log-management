package com.idris.service2;

import java.time.LocalDateTime;
import org.springframework.http.ResponseEntity;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/log")
public class LogController {

    private final KafkaTemplate<String, String> kafkaTemplate;

    public LogController(KafkaTemplate<String, String> kafkaTemplate) {
        this.kafkaTemplate =     kafkaTemplate;
    }

    @GetMapping
    public ResponseEntity<String> log(@RequestParam(defaultValue = "Test log message") String message) {
        String logMessage = "[" + LocalDateTime.now() + "] " + message;
        kafkaTemplate.send("logs", logMessage);
        return ResponseEntity.ok("Log sent to Kafka: " + logMessage);
    }
}
