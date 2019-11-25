#!/usr/bin/env bash

source ${MESOS_TEST_DIR}/common.sh

function run_test {
    local description="$1"
    local command="$2"
    local skip_check_exceptions=${3:-}

    printf "\n==============================================================================\n"
    printf "Running '${description}'\n"
    printf "==============================================================================\n"

    # used to randomize created directories
    export TEST_DATA_DIR=$TEST_INFRA_DIR/temp-test-directory-$(date +%S%N)
    echo "TEST_DATA_DIR: $TEST_DATA_DIR"

    start_timer

    function test_error() {
      echo "[FAIL] Test script contains errors."
      post_test_validation 1 "$description" "$skip_check_exceptions"
    }
    trap 'test_error' ERR

    ${command}
    exit_code="$?"
    post_test_validation ${exit_code} "$description" "$skip_check_exceptions"
}

# Validates the test result and exit code after its execution.
function post_test_validation {
    local exit_code="$1"
    local description="$2"
    local skip_check_exceptions="$3"

    local time_elapsed=$(end_timer)

    if [[ "${skip_check_exceptions}" != "skip_check_exceptions" ]]; then
        check_logs_for_errors
        check_logs_for_exceptions
        check_logs_for_non_empty_out_files
    else
        echo "Checking of logs skipped."
    fi

    # Investigate exit_code for failures of test executable as well as EXIT_CODE for failures of the test.
    # Do not clean up if either fails.
    if [[ ${exit_code} == 0 ]]; then
        if [[ ${EXIT_CODE} != 0 ]]; then
            printf "\n[FAIL] '${description}' failed after ${time_elapsed}! Test exited with exit code 0 but the logs contained errors, exceptions or non-empty .out files\n\n"
            exit_code=1
        else
            printf "\n[PASS] '${description}' passed after ${time_elapsed}! Test exited with exit code 0.\n\n"
        fi
    else
        if [[ ${EXIT_CODE} != 0 ]]; then
            printf "\n[FAIL] '${description}' failed after ${time_elapsed}! Test exited with exit code ${exit_code} and the logs contained errors, exceptions or non-empty .out files\n\n"
        else
            printf "\n[FAIL] '${description}' failed after ${time_elapsed}! Test exited with exit code ${exit_code}\n\n"
        fi
    fi

    if [[ ${exit_code} == 0 ]]; then
        cleanup
    else
        exit "${exit_code}"
    fi
}

# Shuts down cluster and reverts changes to cluster configs
function cleanup_proc {
    shutdown_all
}

# Cleans up all temporary folders and files
function cleanup_tmp_files {
    rm ${FLINK_DIR}/log/*
    echo "Deleted all files under ${FLINK_DIR}/log/"

    rm -rf ${TEST_DATA_DIR} 2> /dev/null
    echo "Deleted ${TEST_DATA_DIR}"
}

# Shuts down the cluster and cleans up all temporary folders and files.
function cleanup {
    cleanup_proc
    cleanup_tmp_files
}