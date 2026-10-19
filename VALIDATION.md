# Validation

Local verification for the fresh rebuild, 19 October 2026.

| Check | Result |
| --- | --- |
| Maven on Java 21 with isolated H2 | 17 tests passed |
| Same Maven suite against PostgreSQL 17 | 17 tests passed |
| React lint and production build | Passed |
| Playwright through Docker Nginx, Java, PostgreSQL and Mailpit | Passed |
| Flutter static analysis | Passed |
| Flutter workflow/widget tests | 4 passed |
| Flutter web compilation | Passed |
| Android debug APK, application ID in.hostelcc.app | Built |
| Local Docker service health | PostgreSQL, API, web and Mailpit healthy |
| Production Compose configuration | Validated |
| PostgreSQL custom-format backup and separate-database restore | Passed |

The API suite covers OTP expiry/replay/rate limiting, failed SMTP cooldown, logout/revocation, scope isolation and updates, director read-only access, room/mess capacity, announcements, feedback/polls, outing/leave transitions, discipline, maintenance, cloakroom QR replay/chair-first/token exhaustion/returns/relocation, audit/export, CSV validation and atomic import. Pagination and totals are checked with 2,100 synthetic student records.

The browser workflow creates blocks, rooms, staff duties and students; signs in with captured email codes; checks student and scoped staff screens; completes outing departure/return and cloakroom check-in; updates mess polls and discipline; imports 40 students; searches and pages beyond the initial dataset; and selects an imported student when recording an incident. It also checks HttpOnly session handling and page errors. Tests use disposable data in a separate Compose project.

Flutter tests cover duty permissions, OTP sign-in with remember-me, action form submission and scanner request/receipt handling. Compilation and widget tests do not replace physical-device testing.

Not performed here: public EC2 deployment, real SMTP-provider delivery, public DNS/TLS issuance, concurrent peak-load testing on EC2, physical camera scanning, signed Android release, or iOS build/signing. These require the intended infrastructure, mail provider, devices or signing credentials. Local compilation and workflow tests are not evidence that those external checks have passed.

The server image was exercised using Dockerfile.prebuilt and a Maven-verified JAR. The normal multi-stage Dockerfile is provided for CI/workstations; its full JDK image download did not complete in this environment. The prebuilt route avoids that dependency and is used by the Docker browser CI job.
