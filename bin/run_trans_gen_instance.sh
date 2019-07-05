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

# explicitly set necessary values
POSTGRES_USERNAME=${POSTGRES_USERNAME:-postgres}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
SSLMODE=${SSLMODE:-disable}

# default values for container image
PROJECT_ID_GCR=${PROJECT_ID_GCR:-cloud-solutions-images}
IMAGE_CONTAINER_REPO=compute-gcs-postgresql-pitr-trans-gen
IMAGE_VERSION=latest
CUSTOMER_RECORD_CREATE_COUNT=${CUSTOMER_RECORD_CREATE_COUNT:-7200}


# check for required environment variables

check_env "$ZONE" "ZONE: compute zone is required"
check_env "$TRANS_GEN_INSTANCE_NAME" "TRANS_GEN_INSTANCE_NAME is required"
check_env "$PROJECT_ID" "PROJECT_ID is required"
check_env "$POSTGRES_HOST_IP" "POSTGRES_HOST_IP is required"
check_env "$POSTGRES_PASSWORD" "POSTGRES_PASSWORD is required"
check_env "$POSTGRES_PITR_DEMO_DBNAME" "POSTGRES_PITR_DEMO_DBNAME is required"

exit_on_missing_env

gcloud beta compute \
       --project=${PROJECT_ID} instances create-with-container ${TRANS_GEN_INSTANCE_NAME}  \
       --zone=${ZONE} \
       --machine-type=n1-standard-1 \
       --subnet=default \
       --no-address \
       --network-tier=PREMIUM \
       --tags=postgres-db  \
       --scopes=https://www.googleapis.com/auth/cloud-platform \
       --image-family=cos-stable \
       --image-project=cos-cloud \
       --boot-disk-size=10GB \
       --boot-disk-type=pd-standard \
       --boot-disk-device-name=trans-gen-instance \
       --container-image=gcr.io/${PROJECT_ID_GCR}/${IMAGE_CONTAINER_REPO}:${IMAGE_VERSION} \
       --container-restart-policy=always \
       --container-env=USERNAME=${POSTGRES_USERNAME},PASSWORD=${POSTGRES_PASSWORD},PORT=${POSTGRES_PORT},HOST=${POSTGRES_HOST_IP},DBNAME=${POSTGRES_PITR_DEMO_DBNAME},SSLMODE=${SSLMODE} \
       --container-arg=${CUSTOMER_RECORD_CREATE_COUNT}
