#!/usr/bin/env bash

# Enable this line when developing a new end-to-end test
#set -Eexuo pipefail
set -o pipefail

if [[ -z $FLINK_DIR ]]; then
    echo "FLINK_DIR needs to point to a Flink distribution directory"
    exit 1
fi

case "$(uname -s)" in
    Linux*)     OS_TYPE=linux;;
    Darwin*)    OS_TYPE=mac;;
    CYGWIN*)    OS_TYPE=cygwin;;
    MINGW*)     OS_TYPE=mingw;;
    *)          OS_TYPE="UNKNOWN:${unameOut}"
esac

export EXIT_CODE=0
FLINK_VERSION=$(cat ${END_TO_END_DIR}/pom.xml | sed -n 's/.*<version>\(.*\)<\/version>/\1/p')

# Starts the timer. Note that nested timers are not supported.
function start_timer {
    SECONDS=0
}

# prints the number of minutes and seconds that have elapsed since the last call to start_timer
function end_timer {
    duration=$SECONDS
    echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds"
}

function check_logs_for_errors {
  echo "Checking for errors..."
  error_count=$(grep -rv "GroupCoordinatorNotAvailableException" $FLINK_DIR/log \
      | grep -v "RetriableCommitFailedException" \
      | grep -v "NoAvailableBrokersException" \
      | grep -v "Async Kafka commit failed" \
      | grep -v "DisconnectException" \
      | grep -v "AskTimeoutException" \
      | grep -v "Error while loading kafka-version.properties" \
      | grep -v "WARN  akka.remote.transport.netty.NettyTransport" \
      | grep -v "WARN  org.apache.flink.shaded.akka.org.jboss.netty.channel.DefaultChannelPipeline" \
      | grep -v "jvm-exit-on-fatal-error" \
      | grep -v '^INFO:.*AWSErrorCode=\[400 Bad Request\].*ServiceEndpoint=\[https://.*\.s3\.amazonaws\.com\].*RequestType=\[HeadBucketRequest\]' \
      | grep -v "RejectedExecutionException" \
      | grep -v "An exception was thrown by an exception handler" \
      | grep -v "java.lang.NoClassDefFoundError: org/apache/hadoop/yarn/exceptions/YarnException" \
      | grep -v "java.lang.NoClassDefFoundError: org/apache/hadoop/conf/Configuration" \
      | grep -v "org.apache.flink.fs.shaded.hadoop3.org.apache.commons.beanutils.FluentPropertyBeanIntrospector  - Error when creating PropertyDescriptor for public final void org.apache.flink.fs.shaded.hadoop3.org.apache.commons.configuration2.AbstractConfiguration.setProperty(java.lang.String,java.lang.Object)! Ignoring this property." \
      | grep -v "Error while loading kafka-version.properties :null" \
      | grep -v "Failed Elasticsearch item request" \
      | grep -v "[Terror] modules" \
      | grep -ic "error" || true)
  if [[ ${error_count} -gt 0 ]]; then
    echo "Found error in log files:"
    cat $FLINK_DIR/log/*
    EXIT_CODE=1
  else
    echo "No errors in log files."
  fi
}

function check_logs_for_exceptions {
  echo "Checking for exceptions..."
  exception_count=$(grep -rv "GroupCoordinatorNotAvailableException" $FLINK_DIR/log \
   | grep -v "RetriableCommitFailedException" \
   | grep -v "NoAvailableBrokersException" \
   | grep -v "Async Kafka commit failed" \
   | grep -v "DisconnectException" \
   | grep -v "AskTimeoutException" \
   | grep -v "WARN  akka.remote.transport.netty.NettyTransport" \
   | grep -v  "WARN  org.apache.flink.shaded.akka.org.jboss.netty.channel.DefaultChannelPipeline" \
   | grep -v '^INFO:.*AWSErrorCode=\[400 Bad Request\].*ServiceEndpoint=\[https://.*\.s3\.amazonaws\.com\].*RequestType=\[HeadBucketRequest\]' \
   | grep -v "RejectedExecutionException" \
   | grep -v "An exception was thrown by an exception handler" \
   | grep -v "Caused by: java.lang.ClassNotFoundException: org.apache.hadoop.yarn.exceptions.YarnException" \
   | grep -v "Caused by: java.lang.ClassNotFoundException: org.apache.hadoop.conf.Configuration" \
   | grep -v "java.lang.NoClassDefFoundError: org/apache/hadoop/yarn/exceptions/YarnException" \
   | grep -v "java.lang.NoClassDefFoundError: org/apache/hadoop/conf/Configuration" \
   | grep -v "java.lang.Exception: Execution was suspended" \
   | grep -v "java.io.InvalidClassException: org.apache.flink.formats.avro.typeutils.AvroSerializer" \
   | grep -v "Caused by: java.lang.Exception: JobManager is shutting down" \
   | grep -v "java.lang.Exception: Artificial failure" \
   | grep -v "org.apache.flink.runtime.checkpoint.CheckpointException" \
   | grep -v "org.elasticsearch.ElasticsearchException" \
   | grep -v "Elasticsearch exception" \
   | grep -ic "exception" || true)
  if [[ ${exception_count} -gt 0 ]]; then
    echo "Found exception in log files:"
    cat $FLINK_DIR/log/*
    EXIT_CODE=1
  else
    echo "No exceptions in log files."
  fi
}

function check_logs_for_non_empty_out_files {
  echo "Checking for non-empty .out files..."
  # exclude reflective access warnings as these are expected (and currently unavoidable) on Java 9
  if grep -ri -v \
    -e "WARNING: An illegal reflective access" \
    -e "WARNING: Illegal reflective access"\
    -e "WARNING: Please consider reporting"\
    -e "WARNING: Use --illegal-access"\
    -e "WARNING: All illegal access"\
    $FLINK_DIR/log/*.out\
   | grep "." \
   > /dev/null; then
    echo "Found non-empty .out files:"
    cat $FLINK_DIR/log/*.out
    EXIT_CODE=1
  else
    echo "No non-empty .out files."
  fi
}

# Kills all job manager.
function jm_kill_all {
  kill_all 'MesosSessionClusterEntrypoint'
}

# Kills all task manager.
function tm_kill_all {
  kill_all 'TaskManagerRunner|TaskManager'
}

# Kills all processes that match the given name.
function kill_all {
  local pid=`jps | grep -E "${1}" | cut -d " " -f 1 || true`
  kill ${pid} 2> /dev/null || true
  wait ${pid} 2> /dev/null || true
}

function shutdown_all {
  stop_cluster
  tm_kill_all
  jm_kill_all
}

REST_PROTOCOL="http"
NODENAME="localhost"
CURL_SSL_ARGS=""

function wait_dispatcher_running {
  # wait at most 10 seconds until the dispatcher is up
  local QUERY_URL="${REST_PROTOCOL}://${NODENAME}:${REST_PORT}/taskmanagers"
  local TIMEOUT=20
  for i in $(seq 1 ${TIMEOUT}); do
    # without the || true this would exit our script if the JobManager is not yet up
    QUERY_RESULT=$(curl ${CURL_SSL_ARGS} "$QUERY_URL" 2> /dev/null || true)

    # ensure the taskmanagers field is there at all
    if [[ ${QUERY_RESULT} =~ \{\"taskmanagers\":\[.*\]\} ]]; then
      echo "Dispatcher REST endpoint is up."
      return
    fi

    echo "Waiting for dispatcher REST endpoint to come up..."
    sleep 1
  done
  echo "Dispatcher REST endpoint has not started within a timeout of ${TIMEOUT} sec"
  exit 1
}

function start_cluster {
  "$FLINK_DIR"/bin/mesos-appmaster.sh -Dmesos.master=${MESOS_MASTER} -Drest.port=${REST_PORT} &
  wait_dispatcher_running
}

JOB_ID_REGEX_EXTRACTOR=".*JobID ([0-9,a-f]*)"

function extract_job_id_from_job_submission_return() {
    if [[ $1 =~ $JOB_ID_REGEX_EXTRACTOR ]];
        then
            JOB_ID="${BASH_REMATCH[1]}";
        else
            JOB_ID=""
        fi
    echo "$JOB_ID"
}