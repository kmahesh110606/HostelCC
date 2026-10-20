#!/usr/bin/env bash
set -euo pipefail
umask 077
revision=${1:?commit SHA required}
registry=${2:?ECR registry required}
region=${3:?AWS region required}
[[ "$revision" =~ ^[a-f0-9]{40}$ ]]
[[ "$registry" =~ ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com$ ]]
[[ "$region" =~ ^[a-z0-9-]+$ ]]
base=/opt/hostelcc
release="$base/releases/$revision"
exec 9>"$base/deploy.lock"
flock -n 9 || { echo "Another deployment is running"; exit 1; }
test -s "$base/.env.deploy" || { echo "Configure /opt/hostelcc/.env.deploy first"; exit 1; }
cd "$release"
export SERVER_IMAGE="$registry/hostelcc-server:$revision"
export WEB_IMAGE="$registry/hostelcc-web:$revision"
export BACKUP_DIRECTORY="$base/backups"
compose=(docker compose --project-name hostelcc --env-file "$base/.env.deploy" -f docker-compose.yml -f docker-compose.production.yml -f docker-compose.backup.yml)
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
"${compose[@]}" config --quiet
"${compose[@]}" pull
# Back up the currently running database before migrations. Never delete volumes.
database=$("${compose[@]}" ps -q postgres)
if [[ -n "$database" ]]; then
    mkdir -p "$BACKUP_DIRECTORY"
    docker exec "$database" pg_dump -U hostelcc -d hostelcc -Fc -f /tmp/predeploy.dump
    docker cp "$database:/tmp/predeploy.dump" "$BACKUP_DIRECTORY/predeploy-$(date -u +%Y%m%dT%H%M%SZ).dump"
fi
# Failed releases keep their logs and do not overwrite the last successful marker.
# Database migrations make automatic image rollback unsafe.
"${compose[@]}" up -d --no-build --wait --wait-timeout 240
curl --fail --silent --show-error http://127.0.0.1:8080/api/health >/dev/null
curl --fail --silent --show-error --range 0-3 http://127.0.0.1:8080/downloads/HostelCC.apk -o /dev/null
printf '%s\n' "$revision" > "$base/current-release"
echo "Deployed $revision"
