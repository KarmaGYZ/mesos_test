#!/usr/bin/env bash

# Common variable
MESOS_TEST_DIR="`dirname \"$0\"`" # relative
MESOS_TEST_DIR="`( cd \"${MESOS_TEST_DIR}\" && pwd -P)`" # absolutized and normalized

# User specify configuration of mesos
export MESOS_MASTER="127.0.0.1:5050"
export REST_PORT="8078"

FLINK_HOME=/Users/yangze/Desktop/flink

export FLINK_DIR=${FLINK_HOME}/build-target
export TEST_DATA_DIR=${MESOS_TEST_DIR}/out
export END_TO_END_DIR=${FLINK_HOME}/flink-end-to-end-tests
export TEST_INFRA_DIR=${END_TO_END_DIR}/test-scripts

source "${MESOS_TEST_DIR}/test-runner-common.sh"

echo "flink-end-to-end-test directory: $END_TO_END_DIR"
echo "Flink distribution directory: $FLINK_DIR"

################################################################################
# Miscellaneous
################################################################################

run_test "Flink CLI end-to-end test" "$MESOS_TEST_DIR/test_cli.sh"

