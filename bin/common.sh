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

# exit upon command failure
set -e

# due to return test logic, store last command
trap 'CMD_ERROR=$CMD_RETURN_CODE_TEST; CMD_RETURN_CODE_TEST=$CMD_CURRENT; CMD_CURRENT=$BASH_COMMAND' DEBUG
# output error before exit
trap 'RETURN_CODE=$?; if [ $RETURN_CODE -ne 0 ]; then echo "<< ${CMD_ERROR} >> returned code $RETURN_CODE."; fi' EXIT

###################
# common functions
###################

check_env () {
  if [ "$1" == "" ]; then
      echo $2
      ENV_ERROR_LIST=True
  fi
}

exit_on_missing_env () {
  if [ "${ENV_ERROR_LIST}" != "" ]; then
      exit
  fi
}
