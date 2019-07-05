#!/bin/bash

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

# source common elements
source common.sh

# instance values
VPC_NETWORK=default
VPC_SUBNET=default
MACHINE_TYPE=n1-standard-1

# cloud init templates
CLOUD_INIT_YAML_PATH=../yaml
CLOUD_INIT_YAML=${CLOUD_INIT_YAML_PATH}/cloud-init-pitr.yaml
CLOUD_INIT_YAML_TEMPLATE=${CLOUD_INIT_YAML}.tpl

# template variables (must be exported)
export POSTGRES_PORT=${POSTGRES_PORT:-5432}
export GCSFUSE_IMAGE=gcr.io/cloud-solutions-images/gcsfuse-ubuntu
export HOST_WAL_RECOVER_PATH=/mnt/disks/wal/pg_wal_recover
export PG_WAL_RECOVER_PATH=/var/lib/postgresql/wal/pg_wal_recover

# check for required environment variables

check_env "$ZONE" "ZONE: compute zone is required"
check_env "$PG_INSTANCE_NAME" "PG_INSTANCE_NAME: is required"
check_env "$PROJECT_ID" "PROJECT_ID: is required"
check_env "$RECOVER_BUCKET" "RECOVER_BUCKET: is required"
check_env "$POSTGRES_PASSWORD" "POSTGRES_PASSWORD: is required"
check_env "$PIT_RECOVERY_TARGET" "PIT_RECOVERY_TARGET: is required"

exit_on_missing_env

# assemble variables
DISK_TYPE=projects/${PROJECT_ID}/zones/${ZONE}/diskTypes/pd-standard

TARGET_FOR_INSTANCE_NAME=$(echo ${PIT_RECOVERY_TARGET} | sed 's/[^0-9A-Za-z]*//g' | awk '{print tolower($0)}')
# export since used by template
export PITR_INSTANCE_NAME=${PG_INSTANCE_NAME}-${TARGET_FOR_INSTANCE_NAME}

PG_DATA_VOLUME=${PITR_INSTANCE_NAME}-data
PG_DATA_VOLUME_SIZE=200
PG_WAL_VOLUME=${PITR_INSTANCE_NAME}-wal
PG_WAL_VOLUME_SIZE=100

# obtain most recent persistent disk snapshot

PG_DATA_VOLUME_ORIGINAL=${PG_INSTANCE_NAME}-data
PG_WAL_VOLUME_ORIGINAL=${PG_INSTANCE_NAME}-wal

# formats accpeted for recovery target
#   YYYY-MM-DD HH:MM:SS.999999+00
#   YYYY-MM-DD HH:MM:SS.999999 UTC
SNAPSHOT_FILTER_LOW=''$(echo $PIT_RECOVERY_TARGET | \
                     awk '{if (NF==3)
                             {print $1" 00:00:00 "$3}
                           else
                             {split($2,a,"+");
                           print $1" 00:00:00+"a[2]}}')
SNAPSHOT_FILTER_HIGH=$PIT_RECOVERY_TARGET

DATA_VOLUME_SNAPSHOT_FOR_PITR=$(gcloud compute snapshots list \
                                       --filter="creationTimestamp > '$SNAPSHOT_FILTER_LOW' \
                                            AND  creationTimestamp < '$SNAPSHOT_FILTER_HIGH'  \
                                            AND  sourceDisk ~ $PG_DATA_VOLUME_ORIGINAL " \
                                       --format="json" | jq --raw-output ".[-1].name")

if [ _${DATA_VOLUME_SNAPSHOT_FOR_PITR} == _null ]; then
  echo "Error: Persistent disk snapshot for data volume" \
       "[${PG_DATA_VOLUME_ORIGINAL}] does not exist for specificed target"
  exit
fi

WAL_VOLUME_SNAPSHOT_FOR_PITR=$(gcloud compute snapshots list \
                                       --filter="creationTimestamp > '$SNAPSHOT_FILTER_LOW' \
                                            AND  creationTimestamp < '$SNAPSHOT_FILTER_HIGH'  \
                                            AND  sourceDisk ~ $PG_WAL_VOLUME_ORIGINAL " \
                                       --format="json" | jq --raw-output ".[-1].name")

if [ _${WAL_VOLUME_SNAPSHOT_FOR_PITR} == _null ]; then
  echo "Error: Persistent disk snapshot for WAL volume" \
       "[${PG_WAL_VOLUME_ORIGINAL}] does not exist for specificed target"
  exit
fi

# generate cloudinit configuration from template
cat $CLOUD_INIT_YAML_TEMPLATE | envsubst > $CLOUD_INIT_YAML

gcloud compute  \
       --project=${PROJECT_ID} instances create ${PITR_INSTANCE_NAME}  \
       --zone=${ZONE} \
       --machine-type=${MACHINE_TYPE} \
       --network=${VPC_NETWORK} \
       --subnet=${VPC_SUBNET} \
       --no-address \
       --network-tier=PREMIUM  \
       --tags=postgres-db  \
       --scopes=https://www.googleapis.com/auth/cloud-platform \
       --image-family=cos-stable \
       --image-project=cos-cloud  \
       --boot-disk-size=10GB  \
       --boot-disk-type=pd-standard  \
       --boot-disk-device-name=${PITR_INSTANCE_NAME}  \
       --create-disk=mode=rw,size=${PG_DATA_VOLUME_SIZE},type=${DISK_TYPE},name=${PG_DATA_VOLUME},device-name=${PG_DATA_VOLUME},source-snapshot=${DATA_VOLUME_SNAPSHOT_FOR_PITR}  \
       --create-disk=mode=rw,size=${PG_WAL_VOLUME_SIZE},type=${DISK_TYPE},name=${PG_WAL_VOLUME},device-name=${PG_WAL_VOLUME},source-snapshot=${WAL_VOLUME_SNAPSHOT_FOR_PITR} \
       --metadata-from-file  user-data=${CLOUD_INIT_YAML}
