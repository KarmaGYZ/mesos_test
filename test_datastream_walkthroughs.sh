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

# End to end test for quick starts test.
# Usage:
# FLINK_DIR=<flink dir> flink-end-to-end-tests/test-scripts/test_datastream_walkthroughs.sh <Type (java or scala)>

source "$(dirname "$0")"/common.sh

TEST_TYPE=$1

mkdir -p "${TEST_DATA_DIR}"
cd "${TEST_DATA_DIR}"

ARTIFACT_ID=flink-walkthrough-datastream-${TEST_TYPE}
ARTIFACT_VERSION=0.1

mvn archetype:generate                                          \
    -DarchetypeGroupId=org.apache.flink                         \
    -DarchetypeArtifactId=flink-walkthrough-datastream-${TEST_TYPE}  \
    -DarchetypeVersion=${FLINK_VERSION}                         \
    -DgroupId=org.apache.flink.walkthrough                      \
    -DartifactId=${ARTIFACT_ID}                                 \
    -DarchetypeCatalog=local \
    -Dversion=${ARTIFACT_VERSION}                               \
    -Dpackage=org.apache.flink.walkthrough                      \
    -DinteractiveMode=false

cd "${ARTIFACT_ID}"

mvn clean package -nsu > compile-output.txt

if [[ `grep -c "BUILD FAILURE" compile-output.txt` -eq '1' ]]; then
    echo "Failure: The walkthrough did not successfully compile"
    cat compile-output.txt
    exit 1
fi

cd target
jar tvf ${ARTIFACT_ID}-${ARTIFACT_VERSION}.jar > contentsInJar.txt

if [[ `grep -c "org/apache/flink/api/java" contentsInJar.txt` -eq '0' && \
      `grep -c "org/apache/flink/streaming/api" contentsInJar.txt` -eq '0' && \
      `grep -c "org/apache/flink/streaming/experimental" contentsInJar.txt` -eq '0' && \
      `grep -c "org/apache/flink/streaming/runtime" contentsInJar.txt` -eq '0' && \
      `grep -c "org/apache/flink/streaming/util" contentsInJar.txt` -eq '0' ]]; then

    echo "Success: There are no flink core classes are contained in the jar."
else
    echo "Failure: There are flink core classes are contained in the jar."
    exit 1
fi

TEST_PROGRAM_JAR=${TEST_DATA_DIR}/${ARTIFACT_ID}/target/${ARTIFACT_ID}-${ARTIFACT_VERSION}.jar

start_cluster

JOB_ID=""
EXIT_CODE=0

RETURN=`$FLINK_DIR/bin/flink run -m localhost:${REST_PORT} -d $TEST_PROGRAM_JAR`
echo "$RETURN"
JOB_ID=`extract_job_id_from_job_submission_return "$RETURN"`
EXIT_CODE=$? # expect matching job id extraction

if [ $EXIT_CODE == 0 ]; then
    RETURN=`$FLINK_DIR/bin/flink list -m localhost:${REST_PORT} -r`
    echo "$RETURN"
    if [[ `grep -c "$JOB_ID" "$RETURN"` -eq '1'  ]]; then # expect match for running job
        echo "[FAIL] Unable to submit walkthrough"
        EXIT_CODE=1
    fi
fi

if [ $EXIT_CODE == 0 ]; then
    eval "$FLINK_DIR/bin/flink cancel -m localhost:${REST_PORT} ${JOB_ID}"
    EXIT_CODE=$?
fi

exit $EXIT_CODE
