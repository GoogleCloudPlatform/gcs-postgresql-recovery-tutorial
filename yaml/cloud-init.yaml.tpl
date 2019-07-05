#cloud-config

# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

final_message: "Postgres instance set up via cloud-init: complete"

# [START cloud_init]
write_files:
- path: /var/tmp/docker-entrypoint-initdb.d/init-pitr-demo-db.sql
  permissions: 0644
  owner: root
  content: |
    CREATE DATABASE ${POSTGRES_PITR_DEMO_DBNAME};

    \c ${POSTGRES_PITR_DEMO_DBNAME}

    CREATE SCHEMA pitr_db_schema;

    CREATE TABLE pitr_db_schema.customer
       (id SERIAL NOT NULL,
        name VARCHAR(255),
        create_timestamp TIMESTAMP DEFAULT current_timestamp,
        PRIMARY KEY (id));

    CREATE TABLE pitr_db_schema.invoice
       (id SERIAL NOT NULL,
        customer_id INTEGER
          REFERENCES pitr_db_schema.customer(id),
        description VARCHAR(1000),
        create_timestamp TIMESTAMP DEFAULT current_timestamp,
        PRIMARY KEY (customer_id, id));

- path: /etc/systemd/system/postgres.service
  permissions: 0644
  owner: root
  content: |
    [Unit]
    Requires=docker.service
    After=docker.service
    Description=postgres docker container

    [Service]
    TimeoutStartSec=0
    KillMode=none
    Restart=always
    RestartSec=5s
    ExecStartPre=-/usr/bin/docker kill postgres-db
    ExecStartPre=-/usr/bin/docker rm -v postgres-db
    ExecStart=/usr/bin/docker run -u postgres --name postgres-db \
                                  -v /var/tmp/docker-entrypoint-initdb.d:/docker-entrypoint-initdb.d \
                                  -v /mnt/disks/data:/var/lib/postgresql/data \
                                  -v /mnt/disks/wal:/var/lib/postgresql/wal \
                                  -e PGDATA=/var/lib/postgresql/data/pgdata \
                                  -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
                                  -e POSTGRES_INITDB_WALDIR=/var/lib/postgresql/wal/pg_wal \
                                  -p ${POSTGRES_PORT}:${POSTGRES_PORT} \
                               postgres:11-alpine
    ExecStop=-/usr/bin/docker stop postgres-db
    ExecStopPost=-/usr/bin/docker rm postgres-db

- path: /etc/systemd/system/wal_archive.service
  permissions: 0644
  owner: root
  content: |
    [Unit]
    Requires=docker.service postgres.service
    After=docker.service postgres.service
    Description=WAL archive docker container

    [Service]
    TimeoutStartSec=10min
    Type=oneshot
    ExecStart=/usr/bin/docker run --name wal-archive \
                                  -v /mnt/disks/wal/pg_wal_archive:/mnt/wal_archive \
                               google/cloud-sdk:slim gsutil mv /mnt/wal_archive/[0-9A-F]*[0-9A-F] gs://${ARCHIVE_BUCKET}
    ExecStopPost=-/usr/bin/docker rm wal-archive

- path: /etc/systemd/system/wal_archive.timer
  permissions: 0644
  owner: root
  content: |
    [Unit]
    Description=Archive WAL to GCS (every 5 minutes)

    [Timer]
    OnBootSec=5min
    OnUnitInactiveSec=5min
    OnUnitActiveSec=5min

    [Install]
    WantedBy=timers.target

# [END cloud_init]

runcmd:
- systemctl daemon-reload
- systemctl start postgres.service
- systemctl start wal_archive.service
- systemctl start wal_archive.timer
- iptables -w -A INPUT -s ${SUBNETWORK_URI} -p tcp -m tcp --dport ${POSTGRES_PORT} -j ACCEPT

bootcmd:
- test -z $(blkid /dev/disk/by-id/google-${PG_INSTANCE_NAME}-data) && cloud-init-per once mkfs-data mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/google-${PG_INSTANCE_NAME}-data
- test -z $(blkid /dev/disk/by-id/google-${PG_INSTANCE_NAME}-wal) && cloud-init-per once mkfs-wal mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/google-${PG_INSTANCE_NAME}-wal
- mkdir -p /mnt/disks/data
- mkdir -p /mnt/disks/wal
- fsck.ext4 -tvy /dev/disk/by-id/google-${PG_INSTANCE_NAME}-data
- fsck.ext4 -tvy /dev/disk/by-id/google-${PG_INSTANCE_NAME}-wal
- mount -t ext4 /dev/disk/by-id/google-${PG_INSTANCE_NAME}-data  /mnt/disks/data
- mount -t ext4 /dev/disk/by-id/google-${PG_INSTANCE_NAME}-wal  /mnt/disks/wal
- ['useradd', 'postgres', '-K', 'UID_MIN=2000', '-K', 'UID_MAX=4999', '--uid', '70', '-m']
- mkdir -p /mnt/disks/wal/pg_wal
- mkdir -p /mnt/disks/wal/pg_wal_archive
- chown -R postgres /mnt/disks/data
- chown -R postgres /mnt/disks/wal
