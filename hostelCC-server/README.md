# Spring Boot server

Java 21, Spring Boot 4.1.1, Maven wrapper, JDBC and Flyway. Production uses PostgreSQL. See the root README for the complete Docker workflow.

```powershell
./mvnw.cmd -B verify
```

For a standalone development process, copy `.env.example` to `.env.local`, configure SMTP and run `./start-server.ps1 -Build`. The dev profile uses a disposable in-memory H2 database unless DB_URL is supplied. All data disappears when that standalone process stops. Use Docker PostgreSQL for persistent local work. The launcher reads only this directory's `.env.local`.

API routes include `/api/auth/request-code`, `/api/auth/verify-code`, `/api/auth/logout`, `/api/auth/me`, `/api/workspace`, `/api/records/{collection}`, `/api/options/{collection}`, `/api/admin/students/import/validate` and `/api/admin/students/import`. Consult ApiController and AuthController for the complete route contracts. Record pages accept `page`, `size` (1–100), and `q`. Workspace collections contain only their first page and pagination metadata; totals are computed across the authorized dataset.

Student CSV imports are administrator-only, transactional and validated again on commit. The admin export streams domain records and excludes authentication secrets. Raw SQL/database administration remains an infrastructure operation, not an unrestricted SQL endpoint.

Tests default to isolated H2. To run the same suite on an empty disposable PostgreSQL database, set TEST_DB_URL, TEST_DB_USER and TEST_DB_PASSWORD, then run Maven verify. Never point these variables at a database containing live records.

No Python runtime or legacy migration tooling is required.
