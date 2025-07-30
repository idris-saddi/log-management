package com.idris.log_service;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@SpringBootApplication
public class LogServiceApplication {
	
	private static final Logger logger = LoggerFactory.getLogger(LogServiceApplication.class);

	public static void main(String[] args) {
		SpringApplication.run(LogServiceApplication.class, args);
		logger.info("🚀 Hello from LogService – should appear in Graylog!");
	}

}
