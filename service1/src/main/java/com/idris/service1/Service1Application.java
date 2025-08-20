package com.idris.service1;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Service1Application {

    private static final Logger log = LoggerFactory.getLogger(Service1Application.class);

    public static void main(String[] args) {
        SpringApplication.run(Service1Application.class, args);

        log.info("✅ Service1 started successfully!");
        log.warn("⚠️ Service1 test warning log");
        log.error("❌ Service1 encountered an error", new RuntimeException("Boom"));
    }
}
