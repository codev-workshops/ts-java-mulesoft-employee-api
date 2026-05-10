# PTO Balance Endpoint — Integration Tests

End-to-end test suite that validates the **PTO balance** endpoint (`GET /api/{employeeId}/pto/balance`) without requiring Salesforce. It exercises the full request path: OAuth token generation → authenticated API call → PostgreSQL query → JSON response.

## Prerequisites

| Requirement | Notes |
|---|---|
| **PostgreSQL** | Accessible instance with the `api_clients` and `employee_pto` tables (the seed script will create them if missing) |
| **MuleSoft app** | Running locally on `http://localhost:8081` (or set `API_BASE_URL`) |
| **CLI tools** | `curl`, `jq`, `psql` must be on `$PATH` |

## Running the tests

```bash
DB_HOST=localhost \
DB_PORT=5432 \
DB_NAME=mydb \
DB_USER=postgres \
DB_PASSWORD=secret \
bash tests/test-pto-balance.sh
```

All environment variables have sensible defaults except `DB_PASSWORD`, which defaults to an empty string.

You can also override the API base URL:

```bash
API_BASE_URL=https://my-cloudhub-app.example.com \
DB_HOST=my-rds-host.amazonaws.com \
DB_PASSWORD=secret \
bash tests/test-pto-balance.sh
```

## What the tests validate

| # | Test case | Assertion |
|---|---|---|
| 1 | Normal PTO balance (`TEST_EMP001`) | HTTP 200, correct `employeeId`, `ptoBalance` = 120.00, `status` = `success` |
| 2 | Zero PTO balance (`TEST_EMP002`) | HTTP 200, `ptoBalance` = 0.00 |
| 3 | High PTO balance (`TEST_EMP003`) | HTTP 200, `ptoBalance` = 999.99 |
| 4 | Employee not found (`TEST_EMP_MISSING`) | HTTP 404, response contains `error` key |
| 5 | Missing Authorization header | HTTP 401 |
| 6 | Invalid Bearer token | HTTP 401 |
| 7 | DB-to-API accuracy | `pto_balance` in PostgreSQL matches `ptoBalance` returned by the API |

## File overview

| File | Purpose |
|---|---|
| `tests/seed-test-data.sql` | Creates tables (if missing), cleans prior test rows, inserts deterministic test data |
| `tests/test-pto-balance.sh` | Orchestrates seeding, token retrieval, test execution, and cleanup |
| `tests/README.md` | This file |

## Cleanup

The script automatically removes all test rows (`employee_id LIKE 'TEST_EMP%'` and `client_id = 'test_client'`) after the run, so it is safe to execute repeatedly against a shared database.
