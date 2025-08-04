package com.idris.log_service.service;

import com.idris.log_service.dto.LogMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.stereotype.Service;

@Service
public class LogProcessorService {

    private static final Logger logger = LoggerFactory.getLogger(LogProcessorService.class);

    public void process(LogMessage log) {
        try {
            // Add structured fields
            MDC.put("service", log.getService());
            MDC.put("originalTS", log.getTimestamp());
            MDC.put("levelName", log.getLevel().toUpperCase());
            MDC.put("level", log.getLevel());

            // Log based on level
            switch (log.getLevel().toUpperCase()) {
                case "DEBUG" -> logger.debug(log.getMessage());
                case "INFO" -> logger.info(log.getMessage());
                case "WARN", "WARNING" -> logger.warn(log.getMessage());
                case "ERROR" -> logger.error(log.getMessage());
                default -> logger.info("(UNKNOWN LEVEL) " + log.getMessage());
            }
        } finally {
            MDC.clear(); // Prevent data leakage across threads
        }
    }
}
