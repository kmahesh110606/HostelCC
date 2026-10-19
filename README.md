# HostelCC

Hostel management rebuilt with React and Tailwind, Flutter, and Java 21 / Spring Boot 4.1.1 with Maven. PostgreSQL stores application data. There is no Django runtime, SQLite database, password login, laundry module or community module in this repository.

## Start locally with Docker

Install Docker Compose, Java 21 and Node 22.12+. From the repository root in PowerShell:

```powershell
./scripts/setup-local.ps1
cd hostelCC-server
./mvnw.cmd -B verify
cd ..
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml -f docker-compose.prebuilt.yml up --build -d --wait
```

Open http://localhost:8080. Sign in as `admin@hostelcc.local` and read the email code at http://localhost:8025. To use another first administrator, pass `-AdminEmail you@example.edu` when creating the local configuration. An existing configuration is never overwritten. Every role uses email OTP, including the administrator.

Mailpit captures development email; it does not deliver email externally. The initial database contains only the bootstrap administrator. The named PostgreSQL volume survives container restarts. Do not use `down --volumes` on a database you want to retain.

The default server Dockerfile can also build the JAR itself: omit `docker-compose.prebuilt.yml`. Build images on a workstation or CI before transferring them to a small EC2 instance.

## Applications

- `HostelCC-web`: React interface, Tailwind styling, responsive layouts, browser QR scanning.
- `hostelCC-app`: Flutter application, camera scanning, item QR passes, searchable records and CSV import.
- `hostelCC-server`: Spring Boot API, Maven wrapper, Flyway schema, authorization and PostgreSQL access.

## First setup

1. Create hostel blocks, rooms, messes and their permitted blocks.
2. Create staff and assign duty books to blocks, messes or specific cloakrooms.
3. Create students individually or use **People > Import CSV**. Download the template, validate the file, then import. Each file supports 1,000 students and 500 KB; use multiple files for larger intakes. Invalid imports create no accounts. Existing accounts are not overwritten.
4. Create cloakrooms with an item type, capacity and token range. Enable student cloakroom access and assign housekeeping staff to the rooms.
5. In Floor plans, create each block's floors and place numbered rooms, corridors, stairs, lifts and walls. Create rooms first; each room can appear on only one floor.
6. Publish announcements and menus. Create feedback sessions with food items and opening/closing times; enable collection for the mess.

Records use server-side search and pagination. Student, room, location and staff selectors support searching beyond the first page.

## Permissions and workflows

Administrators manage all records, accounts, scopes and settings, and export records. Directors have campus-wide record access and can manage menus, feedback collection and polls. Staff access comes from active duty assignments, rather than a blanket role permission:

| Duty book | Scope and work |
| --- | --- |
| HOSTEL | Assigned block students, announcements and hostel records |
| MESS | Assigned mess menus, anonymous feedback, performance and poll controls |
| OUTINGS | Assigned block outing/leave approval, departure and return |
| DISCIPLINE | Assigned block incidents and ID-card history |
| MAINTENANCE | Assigned block requests and housekeeping assignments |
| CLOAKROOM | Assigned storage room scanning, tokens and item records |

Students see their announcements, menu, feedback, polls, discipline and outing/leave histories. Housekeeping staff process assigned cloakrooms and their assigned maintenance work. The API enforces scope independently of the interface.

Cloakroom passes are separate for each student and item type. A chair must be submitted first. Staff scan the room-specific pass to issue the next token in the configured range. Repeated scans do not issue duplicate tokens. Exhaustion stops submissions until an administrator extends the range. Return and relocation actions retain the record history.

Browser JWTs are stored in HttpOnly cookies; remember-me lasts up to 30 days. Production cookies require HTTPS. CSRF protection applies to cookie-authenticated mutations. Native mobile sessions use a private cookie jar. Deactivated users and revoked duty assignments lose access on subsequent requests.

See [deployment instructions](DEPLOYMENT.md), [verification evidence](VALIDATION.md), and the README in each application.

## Dining and campus records

Admins, directors and assigned food wardens control the feedback switch, sessions, menus and polls. Students see their assigned mess menu and may submit one anonymous response per open session, rating the caterer and every listed food item, with an optional comment or complaint. Participation is stored separately from responses; responses contain no student ID or timestamp. Avoid identifying yourself in free-text comments. Caterer accounts see only their assigned mess feedback. Management sees caterer averages and individual food-item performance.

Menus can be edited by day or uploaded as CSV or JSON. Templates are available in the web menu screen. Students are assigned to messes manually or through student CSV import; there is no VTOP integration, mess-change workflow or caterer capacity.

Scoped wardens and supervisors can open a floor, select a room and view occupants, then a student's profile, mess, outing/leave, discipline, cloakroom and entry/exit records. The separate entry/exit register records alternating movements. Administrators can define named duty books using the existing permission families and revoke a book and its assignments.

Reports support record selection, search, columns, CSV exports for Excel and PDF output (browser print or native PDF sharing). Optional Compose services provide scheduled database backups and CSV reports, plus a local database administration console; see DEPLOYMENT.md.

The native Flutter app caches authorized reads in encrypted device storage for up to 15 minutes, limited to 60 entries and 1 MB. Cached data is isolated by server, user and scope; logout, denied access and permission changes clear it. Offline views show when the data was saved and require a connection for changes. There are no push notifications.
