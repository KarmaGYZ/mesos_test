#!/usr/bin/env bash

# Common variable
MESOS_TEST_DIR="`dirname \"$0\"`" # relative
export MESOS_TEST_DIR="`( cd \"${MESOS_TEST_DIR}\" && pwd -P)`" # absolutized and normalized

# User specify configuration of mesos
export MESOS_MASTER="127.0.0.1:5050"
export REST_PORT="8077"

source "$(dirname "$0")"/config

# FLINK_HOME=/Users/yangze/Desktop/flink

export FLINK_DIR=${FLINK_HOME}/build-target
export TEST_DATA_DIR=${MESOS_TEST_DIR}/out
export END_TO_END_DIR=${FLINK_HOME}/flink-end-to-end-tests
export TEST_INFRA_DIR=${END_TO_END_DIR}/test-scripts

source "${MESOS_TEST_DIR}/test-runner-common.sh"

echo "flink-end-to-end-test directory: $END_TO_END_DIR"
echo "Flink distribution directory: $FLINK_DIR"

################################################################################
# Checkpointing tests
################################################################################

run_test "Resuming Savepoint (file, async, no parallelism change) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 2 2 file true"
run_test "Resuming Savepoint (file, sync, no parallelism change) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 2 2 file false"
run_test "Resuming Savepoint (file, async, scale up) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 2 4 file true"
run_test "Resuming Savepoint (file, sync, scale up) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 2 4 file false"
run_test "Resuming Savepoint (file, async, scale down) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 4 2 file true"
run_test "Resuming Savepoint (file, sync, scale down) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 4 2 file false"
run_test "Resuming Savepoint (rocks, no parallelism change, heap timers) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 2 2 rocks false heap"
run_test "Resuming Savepoint (rocks, scale up, heap timers) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 2 4 rocks false heap"
run_test "Resuming Savepoint (rocks, scale down, heap timers) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 4 2 rocks false heap"
run_test "Resuming Savepoint (rocks, no parallelism change, rocks timers) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 2 2 rocks false rocks"
run_test "Resuming Savepoint (rocks, scale up, rocks timers) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 2 4 rocks false rocks"
run_test "Resuming Savepoint (rocks, scale down, rocks timers) end-to-end test" "$MESOS_TEST_DIR/test_resume_savepoint.sh 4 2 rocks false rocks"

run_test "Resuming Externalized Checkpoint (file, async, no parallelism change) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 2 file true true"
run_test "Resuming Externalized Checkpoint (file, sync, no parallelism change) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 2 file false true"
run_test "Resuming Externalized Checkpoint (file, async, scale up) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 4 file true true"
run_test "Resuming Externalized Checkpoint (file, sync, scale up) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 4 file false true"
run_test "Resuming Externalized Checkpoint (file, async, scale down) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 4 2 file true true"
run_test "Resuming Externalized Checkpoint (file, sync, scale down) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 4 2 file false true"
run_test "Resuming Externalized Checkpoint (rocks, non-incremental, no parallelism change) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 2 rocks true false"
run_test "Resuming Externalized Checkpoint (rocks, incremental, no parallelism change) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 2 rocks true true"
run_test "Resuming Externalized Checkpoint (rocks, non-incremental, scale up) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 4 rocks true false"
run_test "Resuming Externalized Checkpoint (rocks, incremental, scale up) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 4 rocks true true"
run_test "Resuming Externalized Checkpoint (rocks, non-incremental, scale down) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 4 2 rocks true false"
run_test "Resuming Externalized Checkpoint (rocks, incremental, scale down) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 4 2 rocks true true"

run_test "Resuming Externalized Checkpoint after terminal failure (file, async) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 2 file true false true"
run_test "Resuming Externalized Checkpoint after terminal failure (file, sync) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 2 file false false true"
run_test "Resuming Externalized Checkpoint after terminal failure (rocks, non-incremental) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 2 rocks true false true"
run_test "Resuming Externalized Checkpoint after terminal failure (rocks, incremental) end-to-end test" "$MESOS_TEST_DIR/test_resume_externalized_checkpoints.sh 2 2 rocks true true true"


################################################################################
# Miscellaneous
################################################################################

run_test "Flink CLI end-to-end test" "$MESOS_TEST_DIR/test_cli.sh"

run_test "Heavy deployment end-to-end test" "$MESOS_TEST_DIR/test_heavy_deployment.sh" "skip_check_exceptions"

run_test "Queryable state (rocksdb) end-to-end test" "$MESOS_TEST_DIR/test_queryable_state.sh rocksdb"

run_test "DataSet allround end-to-end test" "$MESOS_TEST_DIR/test_batch_allround.sh" 

run_test "Batch SQL end-to-end test" "$MESOS_TEST_DIR/test_batch_sql.sh"
run_test "Streaming SQL end-to-end test (Old planner)" "$MESOS_TEST_DIR/test_streaming_sql.sh old" "skip_check_exceptions"
run_test "Streaming SQL end-to-end test (Blink planner)" "$MESOS_TEST_DIR/test_streaming_sql.sh blink" "skip_check_exceptions"
run_test "Stateful stream job upgrade end-to-end test" "$MESOS_TEST_DIR/test_stateful_stream_job_upgrade.sh 2 4"

run_test "Walkthrough Table Java nightly end-to-end test" "$MESOS_TEST_DIR/test_table_walkthroughs.sh java"
run_test "Walkthrough Table Scala nightly end-to-end test" "$MESOS_TEST_DIR/test_table_walkthroughs.sh scala"
run_test "Walkthrough DataStream Java nightly end-to-end test" "$MESOS_TEST_DIR/test_datastream_walkthroughs.sh java"
run_test "Walkthrough DataStream Scala nightly end-to-end test" "$MESOS_TEST_DIR/test_datastream_walkthroughs.sh scala"

run_test "State TTL Heap backend end-to-end test" "$MESOS_TEST_DIR/test_stream_state_ttl.sh file"
run_test "State TTL RocksDb backend end-to-end test" "$MESOS_TEST_DIR/test_stream_state_ttl.sh rocks"

run_test "ConnectedComponents iterations with high parallelism end-to-end test" "$MESOS_TEST_DIR/test_high_parallelism_iterations.sh 25"

run_test "State Migration end-to-end test from 1.6" "$MESOS_TEST_DIR/test_state_migration.sh"
run_test "State Evolution end-to-end test" "$MESOS_TEST_DIR/test_state_evolution.sh"

run_test "Wordcount end-to-end test" "$MESOS_TEST_DIR/test_batch_wordcount.sh file"
run_test "class loading end-to-end test" "$MESOS_TEST_DIR/test_streaming_classloader.sh"
run_test "Distributed cache end-to-end test" "$MESOS_TEST_DIR/test_streaming_distributed_cache_via_blob.sh"

# run_test "TPC-H end-to-end test (Blink planner)" "$END_TO_END_DIR/test-scripts/test_tpch.sh" TODO

printf "\n[PASS] All tests passed\n"
exit 0