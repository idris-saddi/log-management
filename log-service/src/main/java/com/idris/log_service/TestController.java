package com.idris.log_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/test")
public class TestController {

    private static final Logger logger = LoggerFactory.getLogger(TestController.class);

    @GetMapping
    public String testLog(@RequestParam String userId) {
        MDC.put("user_id", userId);
        MDC.put("request_id", UUID.randomUUID().toString());

        logger.info("User {} triggered a log request", userId);
        logger.debug("Debugging log for user {}", userId);
        logger.error("Error log for user {}", userId);
        logger.warn("Warning log for user {}", userId);
        logger.trace("Trace log for user {}", userId);
        // Simulate some processing
        try {
            Thread.sleep(100);
        } catch (InterruptedException e) {
            logger.error("Thread was interrupted", e);
        }
        // Clear MDC to avoid memory leaks
        logger.info("Finished processing log request for user {}", userId);
        logger.debug("Clearing MDC for user {}", userId);
        logger.error("Error log after processing for user {}", userId);
        logger.warn("Warning log after processing for user {}", userId);
        logger.trace("Trace log after processing for user {}", userId);
        // Clear MDC to avoid memory leaks
        MDC.clear();
        System.out.println("Log sent to Graylog with user_id: " + userId);

        return "Log sent!";
    }
}
