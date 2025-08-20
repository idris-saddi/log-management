package com.idris.service2;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Service2Application {

    private static final Logger log = LoggerFactory.getLogger(Service2Application.class);

    public static void main(String[] args) {
        SpringApplication.run(Service2Application.class, args);

        log.info("✅ Service2 started successfully!");
        log.warn("⚠️ Service2 test warning log");
        log.error("❌ Service2 encountered an error", new RuntimeException("Boom"));
    }
}
