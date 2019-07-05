# Copyright 2019 Google LLC
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

# exit upon command failure
set -e

# store last command
trap 'CMD_LAST=$CMD_CURRENT; CMD_CURRENT=$BASH_COMMAND' DEBUG
# output error before exit
trap 'RETURN_CODE=$?; if [ $RETURN_CODE -ne 0 ]; then echo "[ ${CMD_LAST} ] returned code $RETURN_CODE."; fi' EXIT


PROJECT_ID_GCR=${PROJECT_ID_GCR:-$PROJECT_ID}

if [ _$PROJECT_ID_GCR == _ ];  then
  echo "Error: either PROJECT_ID_GCR or PROJECT_ID must "\
       "be set to specfify project for Cloud Container Registry"
  exit
fi

# default values for container image
IMAGE_CONTAINER_REPO=compute-gcs-postgresql-pitr-trans-gen
IMAGE_VERSION=latest

docker build --tag ${IMAGE_CONTAINER_REPO}:${IMAGE_VERSION} \
             --tag gcr.io/${PROJECT_ID_GCR}/${IMAGE_CONTAINER_REPO}:${IMAGE_VERSION} \
            .
docker push  gcr.io/${PROJECT_ID_GCR}/${IMAGE_CONTAINER_REPO}:${IMAGE_VERSION}
