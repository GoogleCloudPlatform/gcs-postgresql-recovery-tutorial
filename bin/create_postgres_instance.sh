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
CLOUD_INIT_YAML=${CLOUD_INIT_YAML_PATH}/cloud-init.yaml
CLOUD_INIT_YAML_TEMPLATE=${CLOUD_INIT_YAML}.tpl

# template variables (must be exported)
export POSTGRES_PORT=${POSTGRES_PORT:-5432}

# check for required environment variables

check_env "$ZONE" "ZONE: compute zone is required"
check_env "$PG_INSTANCE_NAME" "PG_INSTANCE_NAME: is required"
check_env "$PROJECT_ID" "PROJECT_ID: is required"
check_env "$ARCHIVE_BUCKET" "ARCHIVE_BUCKET: is required"
check_env "$POSTGRES_PASSWORD" "POSTGRES_PASSWORD: is required"

exit_on_missing_env

# assemble variables
DISK_TYPE=projects/${PROJECT_ID}/zones/${ZONE}/diskTypes/pd-standard

PG_DATA_VOLUME=${PG_INSTANCE_NAME}-data
PG_DATA_VOLUME_SIZE=200
PG_WAL_VOLUME=${PG_INSTANCE_NAME}-wal
PG_WAL_VOLUME_SIZE=100

# generate cloudinit configuration from template
cat $CLOUD_INIT_YAML_TEMPLATE | envsubst > $CLOUD_INIT_YAML

gcloud compute  \
       --project=${PROJECT_ID} instances create ${PG_INSTANCE_NAME}  \
       --zone=${ZONE} \
       --machine-type=${MACHINE_TYPE} \
       --no-address \
       --network=${VPC_NETWORK} \
       --subnet=${VPC_SUBNET} \
       --network-tier=PREMIUM  \
       --tags=postgres-db  \
       --scopes=https://www.googleapis.com/auth/cloud-platform \
       --image-family=cos-stable \
       --image-project=cos-cloud  \
       --boot-disk-size=10GB  \
       --boot-disk-type=pd-standard  \
       --boot-disk-device-name=${PG_INSTANCE_NAME}  \
       --create-disk=mode=rw,size=${PG_DATA_VOLUME_SIZE},type=${DISK_TYPE},name=${PG_DATA_VOLUME},device-name=${PG_DATA_VOLUME}  \
       --create-disk=mode=rw,size=${PG_WAL_VOLUME_SIZE},type=${DISK_TYPE},name=${PG_WAL_VOLUME},device-name=${PG_WAL_VOLUME} \
       --metadata-from-file  user-data=${CLOUD_INIT_YAML}
