#!/bin/sh
set -eu
umask 077
mkdir -p /backups
interval="${BACKUP_INTERVAL_SECONDS:-86400}"
retention="${BACKUP_RETENTION_DAYS:-14}"
case "$interval:$retention" in *[!0-9:]*|:*|*:) echo 'Invalid backup settings' >&2; exit 1;; esac
[ "$interval" -ge 60 ] && [ "$retention" -ge 1 ]
while :; do
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  if pg_dump --no-owner -Fc -f "/backups/hostelcc-$stamp.dump.part"; then
    mv "/backups/hostelcc-$stamp.dump.part" "/backups/hostelcc-$stamp.dump"
    psql -v ON_ERROR_STOP=1 -c "COPY (SELECT b.name AS block, count(u.id) AS active_students FROM blocks b LEFT JOIN users u ON u.block_id=b.id AND u.role='STUDENT' AND u.active=true GROUP BY b.id,b.name ORDER BY b.name) TO STDOUT WITH CSV HEADER" > "/backups/occupancy-$stamp.csv"
    psql -v ON_ERROR_STOP=1 -c "COPY (SELECT m.name AS caterer,i.name AS food_item,count(r.rating) AS responses,avg(r.rating) AS average_rating FROM food_items i JOIN messes m ON m.id=i.mess_id LEFT JOIN item_ratings r ON r.item_id=i.id GROUP BY m.name,i.id,i.name ORDER BY m.name,i.name) TO STDOUT WITH CSV HEADER" > "/backups/food-performance-$stamp.csv"
    psql -v ON_ERROR_STOP=1 -c "COPY (SELECT b.name AS block,o.kind,o.status,count(*) AS records FROM outings o JOIN blocks b ON b.id=o.block_id GROUP BY b.name,o.kind,o.status ORDER BY b.name,o.kind,o.status) TO STDOUT WITH CSV HEADER" > "/backups/outings-$stamp.csv"
    date -u +%Y-%m-%dT%H:%M:%SZ > /backups/last-success
    find /backups -maxdepth 1 -type f \( -name 'hostelcc-*.dump' -o -name 'occupancy-*.csv' -o -name 'food-performance-*.csv' -o -name 'outings-*.csv' \) -mtime "+$retention" -delete
    echo "Backup and reports completed: $stamp"
  else
    echo 'Backup failed; previous backups retained' >&2
    exit 1
  fi
  sleep "$interval"
done
