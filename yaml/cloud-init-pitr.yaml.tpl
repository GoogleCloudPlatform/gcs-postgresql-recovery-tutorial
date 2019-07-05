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

final_message: "Postgres instance point-in-time recovery set up via cloud-init: complete"

write_files:
- path: /mnt/disks/data/pgdata/recovery.conf
  permissions: 0644
  owner: postgres
  content: |
    restore_command = '( test -d $PG_WAL_RECOVER_PATH && cp $PG_WAL_RECOVER_PATH/%f %p ) '
    recovery_target_time='$PIT_RECOVERY_TARGET'
    recovery_target_inclusive=true


- path: /etc/systemd/system/gcsfuse.service
  permissions: 0644
  owner: root
  content: |
    [Unit]
    Requires=docker.service
    After=docker.service
    Description=gcsfuse docker container

    [Service]
    TimeoutStartSec=0
    KillMode=none
    Restart=always
    RestartSec=5s
    RemainAfterExit=yes
    ExecStartPre=-/bin/umount ${HOST_WAL_RECOVER_PATH}
    ExecStartPre=-/usr/bin/docker kill gcsfuse
    ExecStartPre=-/usr/bin/docker rm -v gcsfuse
    ExecStart=/usr/bin/docker run -d \
                                 --name gcsfuse \
                                 --security-opt apparmor:unconfined \
                                 --cap-add SYS_ADMIN --device /dev/fuse \
                                 --mount type=bind,source=${HOST_WAL_RECOVER_PATH},target=/mnt/${RECOVER_BUCKET},bind-propagation=rshared \
                                  ${GCSFUSE_IMAGE} \
                                   gcsfuse  --foreground    -o allow_other \
                                       ${RECOVER_BUCKET}  /mnt/${RECOVER_BUCKET}
    ExecStop=/usr/bin/docker stop gcsfuse
    ExecStopPost=/usr/bin/docker rm gcsfuse
    ExecStopPost=/bin/umount ${HOST_WAL_RECOVER_PATH}



- path: /etc/systemd/system/postgres.service
  permissions: 0644
  owner: root
  content: |
    [Unit]
    Requires=docker.service gcsfuse.service
    After=docker.service gcsfuse.service
    Description=postgres-db docker container

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
                                  --mount type=bind,source=${HOST_WAL_RECOVER_PATH},target=${PG_WAL_RECOVER_PATH},bind-propagation=rshared \
                                  -e PGDATA=/var/lib/postgresql/data/pgdata \
                                  -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
                                  -e POSTGRES_INITDB_WALDIR=/var/lib/postgresql/wal/pg_wal \
                                  -p ${POSTGRES_PORT}:${POSTGRES_PORT} \
                               postgres:11-alpine
    ExecStop=/usr/bin/docker stop postgres-db
    ExecStopPost=/usr/bin/docker rm postgres-db

runcmd:
- systemctl daemon-reload
- systemctl start gcsfuse.service
- systemctl start postgres.service
- iptables -w -A INPUT -s ${SUBNETWORK_URI} -p tcp -m tcp --dport ${POSTGRES_PORT} -j ACCEPT

bootcmd:
- mkdir -p /mnt/disks/data
- mkdir -p /mnt/disks/wal
- fsck.ext4 -tvy /dev/disk/by-id/google-${PITR_INSTANCE_NAME}-data
- fsck.ext4 -tvy /dev/disk/by-id/google-${PITR_INSTANCE_NAME}-wal
- mount -t ext4 /dev/disk/by-id/google-${PITR_INSTANCE_NAME}-data  /mnt/disks/data
- mount -t ext4 /dev/disk/by-id/google-${PITR_INSTANCE_NAME}-wal  /mnt/disks/wal
- ['useradd', 'postgres', '-K', 'UID_MIN=2000', '-K', 'UID_MAX=4999', '--uid', '70', '-m']
- mkdir -p /mnt/disks/wal/pg_wal_recover
- chown -R postgres /mnt/disks/wal
- /bin/sed -i 's/^archive/#&/' /mnt/disks/data/pgdata/postgresql.conf
