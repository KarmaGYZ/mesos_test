#!/usr/bin/env bash
################################################################################
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

source "$(dirname "$0")"/common.sh

INPUT_TYPE=${1:-file}
RESULT_HASH="72a690412be8928ba239c2da967328a5"
case $INPUT_TYPE in
    (file)
        INPUT_ARGS="--input ${TEST_INFRA_DIR}/test-data/words"
    ;;
    (*)
        echo "Unknown input type $INPUT_TYPE"
        exit 1
    ;;
esac

OUTPUT_LOCATION="${TEST_DATA_DIR}/out/wc_out"

mkdir -p "${TEST_DATA_DIR}"

start_cluster

# The test may run against different source types.
# But the sources should provide the same test data, so the checksum stays the same for all tests.
eval "${FLINK_DIR}/bin/flink run -m localhost:${REST_PORT} -p 1 ${FLINK_DIR}/examples/batch/WordCount.jar ${INPUT_ARGS} --output ${OUTPUT_LOCATION}"
check_result_hash "WordCount (${INPUT_TYPE})" "${OUTPUT_LOCATION}" "${RESULT_HASH}"
