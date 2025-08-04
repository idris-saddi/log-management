// package com.idris.service1;

// import java.time.LocalDateTime;
// import org.springframework.http.ResponseEntity;
// import org.springframework.kafka.core.KafkaTemplate;
// import org.springframework.web.bind.annotation.*;

// @RestController
// @RequestMapping("/log")
// public class LogController {

//     private final KafkaTemplate<String, String> kafkaTemplate;

//     public LogController(KafkaTemplate<String, String> kafkaTemplate) {
//         this.kafkaTemplate =     kafkaTemplate;
//     }

//     @GetMapping
//     public ResponseEntity<String> log(@RequestParam(defaultValue = "Test log message") String message) {
//         String logMessage = "[" + LocalDateTime.now() + "] " + message;
//         kafkaTemplate.send("logs", logMessage);
//         return ResponseEntity.ok("Log sent to Kafka: " + logMessage);
//     }
// }

package com.idris.service1;

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

    @PostMapping
    public ResponseEntity<?> postLog(@RequestParam(defaultValue = "Test log message") String message) {
        try {
            Map<String, Object> log = new HashMap<>();
            log.put("timestamp", java.time.Instant.now().toString());
            log.put("message", message);
            log.put("level", "INFO");
            log.put("service", "service1");

            String logJson = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(log);
            kafkaTemplate.send("logs", logJson);
            return ResponseEntity.ok("Log sent to Kafka: " + logJson);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body("Failed to send log: " + e.getMessage());
        }
    }

    @GetMapping
    public ResponseEntity<?> getLog(@RequestParam(defaultValue = "Test log message") String message) {
        try {
            Map<String, Object> log = new HashMap<>();
            log.put("timestamp", java.time.Instant.now().toString());
            log.put("message", message);
            log.put("level", "INFO");
            log.put("service", "service1");

            String logJson = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(log);
            kafkaTemplate.send("logs", logJson);
            return ResponseEntity.ok("Log sent to Kafka: " + logJson);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body("Failed to send log: " + e.getMessage());
        }
    }
}
