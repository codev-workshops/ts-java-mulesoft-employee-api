-- seed-test-data.sql
-- Seeds test data for PTO balance endpoint integration tests.
-- Safe to run multiple times (cleanup runs first).

-- ============================================================
-- Cleanup: Remove any prior test data
-- ============================================================
DELETE FROM employee_pto WHERE employee_id LIKE 'TEST_EMP%';
DELETE FROM api_clients  WHERE client_id = 'test_client';

-- ============================================================
-- Create tables if they don't exist
-- ============================================================
CREATE TABLE IF NOT EXISTS api_clients (
    client_id        VARCHAR(255) PRIMARY KEY,
    client_secret    VARCHAR(255) NOT NULL,
    client_name      VARCHAR(255),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_id          INTEGER,
    access_token     VARCHAR(255),
    expires_at       TIMESTAMP,
    callback_url     VARCHAR(500),
    refresh_token    VARCHAR(500),
    refresh_token_expires_at TIMESTAMP,
    token_expires_at TIMESTAMP,
    salesforce_user_id VARCHAR(255),
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active        BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS employee_pto (
    id            SERIAL PRIMARY KEY,
    employee_id   VARCHAR(50) NOT NULL,
    pto_balance   DECIMAL(10,2) DEFAULT 0,
    accrual_rate  DECIMAL(10,2),
    last_updated  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users (
    user_id       SERIAL PRIMARY KEY,
    username      VARCHAR(255) UNIQUE NOT NULL,
    email         VARCHAR(255) UNIQUE NOT NULL,
    first_name    VARCHAR(255) NOT NULL,
    last_name     VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active     BOOLEAN DEFAULT TRUE
);

-- ============================================================
-- Insert test OAuth client
-- ============================================================
INSERT INTO api_clients (client_id, client_secret, client_name)
VALUES ('test_client', 'test_secret', 'Test Client');

-- ============================================================
-- Insert test PTO records
-- ============================================================
INSERT INTO employee_pto (employee_id, pto_balance, accrual_rate)
VALUES
    ('TEST_EMP001', 120.00,  8.00),   -- normal balance
    ('TEST_EMP002',   0.00,  8.00),   -- zero balance
    ('TEST_EMP003', 999.99,  4.00);   -- high balance / boundary

-- NOTE: No record for TEST_EMP_MISSING (used to verify 404 response)
