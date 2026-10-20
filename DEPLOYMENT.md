# Deployment

## EC2 with Docker Compose

Use an Ubuntu EC2 instance with Docker Engine and the Compose plugin. Point your hostname to the instance. Allow inbound TCP 80 and 443 (UDP 443 is optional for HTTP/3); restrict SSH to your administration address. PostgreSQL and the API have no published production ports.

Copy `.env.example` to `.env.deploy`. Set a strong unique database password, random JWT signing secret (at least 32 bytes), first administrator email, public hostname, matching HTTPS allowed origin and real SMTP provider credentials. There are no administrator passwords. Bootstrap creates the administrator only when the user table is empty.

First run scripts/publish-apk.ps1 with the public HTTPS API URL and your Android release signing configuration. Then build images on a machine with sufficient memory, using Java 21 for the verified JAR:

```sh
cd hostelCC-server
./mvnw -B verify
cd ..
docker compose --env-file .env.deploy -f docker-compose.yml -f docker-compose.prebuilt.yml build
```

Transfer the images with a private registry (set SERVER_IMAGE and WEB_IMAGE to immutable tags in the deployment environment), or `docker image save` / `docker image load`. Copy the source/configuration files needed by Compose and `deploy/Caddyfile` to EC2. Then start without building on the instance:

```sh
docker compose --env-file .env.deploy -f docker-compose.yml -f docker-compose.production.yml up -d --no-build --wait
```

Caddy obtains HTTPS certificates and proxies the browser and API. The server refuses unsafe production configurations, including development secrets, insecure cookies, non-HTTPS origins and the local test mailbox. Do not include the local or verification overrides in production.

Check `/api/health`, sign in through your real mailbox, and exercise a student/staff workflow before opening access. Provider delivery, DNS, certificate issuance and physical-device camera testing require your deployment configuration. The local validation does not certify those external services.

Compose limits PostgreSQL to 192 MB, Java to 384 MB, Nginx to 48 MB and Caddy to 64 MB. Leave memory for the OS and Docker; build images elsewhere. Local pagination tests cover 2,100 students, but concurrent peak traffic still needs measurement on the chosen EC2 instance. Adjust connection/thread limits and memory together if load requires it. `OTP_IP_LIMIT` limits hourly code requests from one IP; set it for expected demand when students share a campus NAT address.

## Backups and updates

Back up PostgreSQL, not the development H2 database. On Linux, with the same Compose configuration used for deployment:

```sh
mkdir -p backups
chmod 700 backups
docker compose --env-file .env.deploy -f docker-compose.yml exec -T postgres pg_dump -U hostelcc -d hostelcc -Fc > backups/hostelcc.dump
chmod 600 backups/hostelcc.dump
```

PowerShell 5 does not preserve binary pipe output. On Windows, write the dump inside the container and copy it out:

```powershell
New-Item -ItemType Directory -Force backups | Out-Null
docker compose --env-file .env.local -f docker-compose.yml exec -T postgres pg_dump -U hostelcc -d hostelcc -Fc -f /tmp/hostelcc.dump
$container = docker compose --env-file .env.local -f docker-compose.yml ps -q postgres
docker cp "${container}:/tmp/hostelcc.dump" backups/hostelcc.dump
```

Keep encrypted backups outside the EC2 instance. Test restoration into a separate database before relying on a backup. Restore using `pg_restore --no-owner --exit-on-error` with the matching PostgreSQL version; never test a restore over the live database.

For updates, back up, load/pull the new image tags and repeat `up -d --no-build --wait`. Flyway applies schema migrations at startup. Retain the previous images; a schema change may require database restoration rather than simply switching images. Preserve the PostgreSQL volume and Caddy certificate volume.

## Local development

The local override exposes HTTP on loopback port 8080 and uses PostgreSQL inside Docker. Localhost temporarily uses DEV_LOGIN_OTP=110606 without SMTP; set DEV_LOGIN_OTP= to test real email delivery. Production always uses your configured SMTP provider. `.env.local` is generated with random secrets. The isolated integration-test override publishes PostgreSQL on loopback 55439; do not use it in production. Native Android emulators use `http://10.0.2.2:8080/api`.

References: [Compose readiness](https://docs.docker.com/compose/how-tos/startup-order/), [Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https).

## Scheduled backups and reports

Add `-f docker-compose.backup.yml` to your Compose command to run daily custom-format PostgreSQL backups and occupancy, outing and food-performance CSV reports. Configure `BACKUP_DIRECTORY` (default `./backups`), `BACKUP_INTERVAL_SECONDS` (86400) and `BACKUP_RETENTION_DAYS` (14). The sidecar writes a `last-success` marker and has a freshness health check. Protect this directory: database backups contain personal records and authentication tables. Copy encrypted backups off the host and periodically restore into a separate database. This optional service adds a 96 MB memory allowance.

For infrastructure database administration, add `-f docker-compose.tools.yml --profile database-tools`. Adminer is available only on `127.0.0.1:8081`; on EC2 use an SSH tunnel. Select PostgreSQL, server `postgres`, database/user `hostelcc`, and the configured database password. This is an infrastructure credential, separate from application email OTP. Stop the optional tool when finished.

Migration V4 removes the old identified feedback records and mess-change tables and removes caterer capacity. This is the fresh-rebuild schema transition; back up any earlier test database before applying it. It does not import Django or SQLite data.

Build and publish the signed release APK before building the web image, using scripts/publish-apk.ps1 with the public HTTPS API URL. The footer serves /downloads/HostelCC.apk directly; missing artifacts return 404 rather than the SPA page. The localhost debug APK targets an Android emulator and must be replaced for deployment. iOS remains disabled until an App Store release is available.

Only automated browser tests use docker-compose.test.yml, an isolated SMTP capture service. It is absent from normal localhost and production startup. Never include this override on a live installation.

For automatic deployment after passing CI, follow [EC2 CI/CD setup](EC2.md). The workflow is disabled until DEPLOY_ENABLED and the AWS resources are configured.
