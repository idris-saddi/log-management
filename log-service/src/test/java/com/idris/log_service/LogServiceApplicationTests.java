package com.idris.log_service;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import org.springframework.test.web.servlet.MockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;

@SpringBootTest
@AutoConfigureMockMvc
class LogServiceApplicationTests {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void contextLoads() {
        // This test just verifies that the context loads successfully.
    }

    @Test
    void testLogEndpoint() throws Exception {
        String userId = "test-user-123";

        mockMvc.perform(get("/test")
                .param("userId", userId))
                .andExpect(status().isOk())
                .andExpect(content().string("Log sent!"));
    }
}
