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

source "${MESOS_TEST_DIR}/common_utils.sh"

# Starts the timer. Note that nested timers are not supported.
function start_timer {
    SECONDS=0
}

# prints the number of minutes and seconds that have elapsed since the last call to start_timer
function end_timer {
    duration=$SECONDS
    echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds"
}

function cancel_job {
  "$FLINK_DIR"/bin/flink cancel -m localhost:${REST_PORT} $1
}

function find_latest_completed_checkpoint {
    local checkpoint_root_directory=$1
    # a completed checkpoint must contain the _metadata file
    local checkpoint_meta_file=$(ls -d ${checkpoint_root_directory}/chk-[1-9]*/_metadata | sort -Vr | head -n1)
    echo "$(dirname "${checkpoint_meta_file}")"
}

function check_result_hash {
  local error_code=0
  check_result_hash_no_exit "$@" || error_code=$?

  if [ "$error_code" != "0" ]
  then
    exit $error_code
  fi
}

function check_result_hash_no_exit {
  local name=$1
  local outfile_prefix=$2
  local expected=$3

  local actual
  if [ "`command -v md5`" != "" ]; then
    actual=$(LC_ALL=C sort $outfile_prefix* | md5 -q)
  elif [ "`command -v md5sum`" != "" ]; then
    actual=$(LC_ALL=C sort $outfile_prefix* | md5sum | awk '{print $1}')
  else
    echo "Neither 'md5' nor 'md5sum' binary available."
    return 2
  fi
  if [[ "$actual" != "$expected" ]]
  then
    echo "FAIL $name: Output hash mismatch.  Got $actual, expected $expected."
    echo "head hexdump of actual:"
    head $outfile_prefix* | hexdump -c
    return 1
  else
    echo "pass $name"
    # Output files are left behind in /tmp
  fi
  return 0
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
  kill_all 'TaskManagerRunner|TaskManager|MesosTaskExecutorRunner'
}

function clean_stdout_files {
    rm ${FLINK_DIR}/log/*.out
    echo "Deleted all stdout files under ${FLINK_DIR}/log/"
}

# Kills all processes that match the given name.
function kill_all {
  local pid=`jps | grep -E "${1}" | cut -d " " -f 1 || true`
  kill ${pid} 2> /dev/null || true
  wait ${pid} 2> /dev/null || true
}

function shutdown_all {
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

function set_config_key() {
    local config_key=$1
    local value=$2
    delete_config_key ${config_key}
    echo "$config_key: $value" >> $FLINK_DIR/conf/flink-conf.yaml
}

function delete_config_key() {
    local config_key=$1
    sed -i -e "/^${config_key}: /d" ${FLINK_DIR}/conf/flink-conf.yaml
}

function setup_flink_slf4j_metric_reporter() {
  INTERVAL="${1:-1 SECONDS}"
  add_optional_lib "metrics-slf4j"
  set_config_key "metrics.reporter.slf4j.class" "org.apache.flink.metrics.slf4j.Slf4jReporter"
  set_config_key "metrics.reporter.slf4j.interval" "${INTERVAL}"
}

function add_optional_lib() {
    local lib_name=$1
    cp "$FLINK_DIR/opt/flink-${lib_name}"*".jar" "$FLINK_DIR/lib"
}

function wait_job_running {
  local TIMEOUT=10
  for i in $(seq 1 ${TIMEOUT}); do
    JOB_LIST_RESULT=$("$FLINK_DIR"/bin/flink list -m localhost:${REST_PORT} -r | grep "$1")

    if [[ "$JOB_LIST_RESULT" == "" ]]; then
      echo "Job ($1) is not yet running."
    else
      echo "Job ($1) is running."
      return
    fi
    sleep 1
  done
  echo "Job ($1) has not started within a timeout of ${TIMEOUT} sec"
  exit 1
}

function get_metric_processed_records {
  OPERATOR=$1
  JOB_NAME="${2:-General purpose test job}"
  N=$(grep ".${JOB_NAME}.$OPERATOR.numRecordsIn:" $FLINK_DIR/log/*taskexecutor*.log | sed 's/.* //g' | tail -1)
  if [ -z $N ]; then
    N=0
  fi
  echo $N
}

function get_num_metric_samples {
  OPERATOR=$1
  JOB_NAME="${2:-General purpose test job}"
  N=$(grep ".${JOB_NAME}.$OPERATOR.numRecordsIn:" $FLINK_DIR/log/*taskexecutor*.log | wc -l)
  if [ -z $N ]; then
    N=0
  fi
  echo $N
}

function wait_job_terminal_state {
  local job=$1
  local expected_terminal_state=$2

  echo "Waiting for job ($job) to reach terminal state $expected_terminal_state ..."

  while : ; do
    local N=$(grep -o "Job $job reached globally terminal state .*" $FLINK_DIR/log/*mesos-appmaster*.log | tail -1 || true)
    if [[ -z $N ]]; then
      sleep 1
    else
      local actual_terminal_state=$(echo $N | sed -n 's/.*state \([A-Z]*\).*/\1/p')
      if [[ -z $expected_terminal_state ]] || [[ "$expected_terminal_state" == "$actual_terminal_state" ]]; then
        echo "Job ($job) reached terminal state $actual_terminal_state"
        break
      else
        echo "Job ($job) is in state $actual_terminal_state but expected $expected_terminal_state"
        exit 1
      fi
    fi
  done
}

function backup_flink_dir() {
    mkdir -p "${TEST_DATA_DIR}/tmp/backup"
    # Note: not copying all directory tree, as it may take some time on some file systems.
    for dirname in ${BACKUP_FLINK_DIRS}; do
        cp -r "${FLINK_DIR}/${dirname}" "${TEST_DATA_DIR}/tmp/backup/"
    done
}

function revert_flink_dir() {

    for dirname in ${BACKUP_FLINK_DIRS}; do
        if [ -d "${TEST_DATA_DIR}/tmp/backup/${dirname}" ]; then
            rm -rf "${FLINK_DIR}/${dirname}"
            mv "${TEST_DATA_DIR}/tmp/backup/${dirname}" "${FLINK_DIR}/"
        fi
    done

    rm -r "${TEST_DATA_DIR}/tmp/backup"

    REST_PROTOCOL="http"
    CURL_SSL_ARGS=""
}

function wait_num_checkpoints {
    JOB=$1
    NUM_CHECKPOINTS=$2

    echo "Waiting for job ($JOB) to have at least $NUM_CHECKPOINTS completed checkpoints ..."

    while : ; do
      N=$(grep -o "Completed checkpoint [1-9]* for job $JOB" $FLINK_DIR/log/*mesos-appmaster*.log | awk '{print $3}' | tail -1)

      if [ -z $N ]; then
        N=0
      fi

      if (( N < NUM_CHECKPOINTS )); then
        sleep 1
      else
        break
      fi
    done
}

function stop_with_savepoint {
  "$FLINK_DIR"/bin/flink stop -m localhost:${REST_PORT} -p $2 $1
}

function print_mem_use_osx {
    declare -a mem_types=("active" "inactive" "wired down")
    used=""
    for mem_type in "${mem_types[@]}"
    do
       used_type=$(vm_stat | grep "Pages ${mem_type}:" | awk '{print $NF}' | rev | cut -c 2- | rev)
       let used_type="(${used_type}*4096)/1024/1024"
       used="$used $mem_type=${used_type}MB"
    done
    let mem=$(sysctl -n hw.memsize)/1024/1024
    echo "Memory Usage: ${used} total=${mem}MB"
}

function print_mem_use {
    if [[ "$OS_TYPE" == "mac" ]]; then
        print_mem_use_osx
    else
        free -m | awk 'NR==2{printf "Memory Usage: used=%sMB total=%sMB %.2f%%\n", $3,$2,$3*100/$2 }'
    fi
}

function wait_oper_metric_num_in_records {
    OPERATOR=$1
    MAX_NUM_METRICS="${2:-200}"
    JOB_NAME="${3:-General purpose test job}"
    NUM_METRICS=$(get_num_metric_samples ${OPERATOR} '${JOB_NAME}')
    OLD_NUM_METRICS=${4:-${NUM_METRICS}}
    # monitor the numRecordsIn metric of the state machine operator in the second execution
    # we let the test finish once the second restore execution has processed 200 records
    while : ; do
      NUM_METRICS=$(get_num_metric_samples ${OPERATOR} "${JOB_NAME}")
      NUM_RECORDS=$(get_metric_processed_records ${OPERATOR} "${JOB_NAME}")

      # only account for metrics that appeared in the second execution
      if (( $OLD_NUM_METRICS >= $NUM_METRICS )) ; then
        NUM_RECORDS=0
      fi

      if (( $NUM_RECORDS < $MAX_NUM_METRICS )); then
        echo "Waiting for job to process up to ${MAX_NUM_METRICS} records, current progress: ${NUM_RECORDS} records ..."
        sleep 1
      else
        break
      fi
    done
}

function take_savepoint {
  "$FLINK_DIR"/bin/flink savepoint -m localhost:${REST_PORT} $1 $2
}

# SSL

function _set_conf_ssl_helper {
    local type=$1 # 'internal' or external 'rest'
    local provider=$2 # 'JDK' or 'OPENSSL'
    local provider_lib=$3 # if using OPENSSL, choose: 'dynamic' or 'static' (how openSSL is linked to our packaged jar)
    local ssl_dir="${TEST_DATA_DIR}/ssl/${type}"
    local password="${type}.password"

    if [ "${type}" != "internal" ] && [ "${type}" != "rest" ]; then
        echo "Unknown type of ssl connectivity: ${type}. It can be either 'internal' or external 'rest'"
        exit 1
    fi
    if [ "${provider}" != "JDK" ] && [ "${provider}" != "OPENSSL" ]; then
        echo "Unknown SSL provider: ${provider}. It can be either 'JDK' or 'OPENSSL'"
        exit 1
    fi
    if [ "${provider_lib}" != "dynamic" ] && [ "${provider_lib}" != "static" ]; then
        echo "Unknown library type for openSSL: ${provider_lib}. It can be either 'dynamic' or 'static'"
        exit 1
    fi

    echo "Setting up SSL with: ${type} ${provider} ${provider_lib}"

    # clean up the dir that will be used for SSL certificates and trust stores
    if [ -e "${ssl_dir}" ]; then
       echo "File ${ssl_dir} exists. Deleting it..."
       rm -rf "${ssl_dir}"
    fi
    mkdir -p "${ssl_dir}"

    SANSTRING="dns:${NODENAME}"
    for NODEIP in $(get_node_ip) ; do
        SANSTRING="${SANSTRING},ip:${NODEIP}"
    done

    echo "Using SAN ${SANSTRING}"

    # create certificates
    keytool -genkeypair -alias ca -keystore "${ssl_dir}/ca.keystore" -dname "CN=Sample CA" -storepass ${password} -keypass ${password} -keyalg RSA -ext bc=ca:true -storetype PKCS12
    keytool -keystore "${ssl_dir}/ca.keystore" -storepass ${password} -alias ca -exportcert > "${ssl_dir}/ca.cer"
    keytool -importcert -keystore "${ssl_dir}/ca.truststore" -alias ca -storepass ${password} -noprompt -file "${ssl_dir}/ca.cer"

    keytool -genkeypair -alias node -keystore "${ssl_dir}/node.keystore" -dname "CN=${NODENAME}" -ext SAN=${SANSTRING} -storepass ${password} -keypass ${password} -keyalg RSA -storetype PKCS12
    keytool -certreq -keystore "${ssl_dir}/node.keystore" -storepass ${password} -alias node -file "${ssl_dir}/node.csr"
    keytool -gencert -keystore "${ssl_dir}/ca.keystore" -storepass ${password} -alias ca -ext SAN=${SANSTRING} -infile "${ssl_dir}/node.csr" -outfile "${ssl_dir}/node.cer"
    keytool -importcert -keystore "${ssl_dir}/node.keystore" -storepass ${password} -file "${ssl_dir}/ca.cer" -alias ca -noprompt
    keytool -importcert -keystore "${ssl_dir}/node.keystore" -storepass ${password} -file "${ssl_dir}/node.cer" -alias node -noprompt

    # keystore is converted into a pem format to use it as node.pem with curl in Flink REST API queries, see also $CURL_SSL_ARGS
    openssl pkcs12 -passin pass:${password} -in "${ssl_dir}/node.keystore" -out "${ssl_dir}/node.pem" -nodes

    if [ "${provider}" = "OPENSSL" -a "${provider_lib}" = "dynamic" ]; then
        cp $FLINK_DIR/opt/flink-shaded-netty-tcnative-dynamic-*.jar $FLINK_DIR/lib/
    elif [ "${provider}" = "OPENSSL" -a "${provider_lib}" = "static" ]; then
        # Flink is not providing the statically-linked library because of potential licensing issues
        # -> we need to build it ourselves
        FLINK_SHADED_VERSION=$(cat ${END_TO_END_DIR}/../pom.xml | sed -n 's/.*<flink.shaded.version>\(.*\)<\/flink.shaded.version>/\1/p')
        echo "BUILDING flink-shaded-netty-tcnative-static"
        git clone https://github.com/apache/flink-shaded.git
        cd flink-shaded
        git checkout "release-${FLINK_SHADED_VERSION}"
        mvn clean package -Pinclude-netty-tcnative-static -pl flink-shaded-netty-tcnative-static
        cp flink-shaded-netty-tcnative-static/target/flink-shaded-netty-tcnative-static-*.jar $FLINK_DIR/lib/
        cd ..
        rm -rf flink-shaded
    fi

    # adapt config
    set_config_key security.ssl.provider ${provider}
    set_config_key security.ssl.${type}.enabled true
    set_config_key security.ssl.${type}.keystore ${ssl_dir}/node.keystore
    set_config_key security.ssl.${type}.keystore-password ${password}
    set_config_key security.ssl.${type}.key-password ${password}
    set_config_key security.ssl.${type}.truststore ${ssl_dir}/ca.truststore
    set_config_key security.ssl.${type}.truststore-password ${password}
}

function _set_conf_mutual_rest_ssl {
    local auth="${1:-server}" # only 'server' or 'mutual'
    local mutual="false"
    local ssl_dir="${TEST_DATA_DIR}/ssl/rest"
    if [ "${auth}" == "mutual" ]; then
        CURL_SSL_ARGS="${CURL_SSL_ARGS} --cert ${ssl_dir}/node.pem"
        mutual="true";
    fi
    echo "Mutual ssl auth: ${mutual}"
    set_config_key security.ssl.rest.authentication-enabled ${mutual}
}

function set_conf_rest_ssl {
    local auth="${1:-server}" # only 'server' or 'mutual'
    local provider="${2:-JDK}" # 'JDK' or 'OPENSSL'
    local provider_lib="${3:-dynamic}" # for OPENSSL: 'dynamic' or 'static'
    local ssl_dir="${TEST_DATA_DIR}/ssl/rest"
    _set_conf_ssl_helper "rest" "${provider}" "${provider_lib}"
    _set_conf_mutual_rest_ssl ${auth}
    REST_PROTOCOL="https"
    CURL_SSL_ARGS="${CURL_SSL_ARGS} --cacert ${ssl_dir}/node.pem"
}

function set_conf_ssl {
    local auth="${1:-server}" # only 'server' or 'mutual'
    local provider="${2:-JDK}" # 'JDK' or 'OPENSSL'
    local provider_lib="${3:-dynamic}" # for OPENSSL: 'dynamic' or 'static'
    _set_conf_ssl_helper "internal" "${provider}" "${provider_lib}"
    set_conf_rest_ssl ${auth} "${provider}" "${provider_lib}"
}

function rollback_openssl_lib() {
  rm $FLINK_DIR/lib/flink-shaded-netty-tcnative-{dynamic,static}-*.jar
}
