#!/usr/bin/env bash

source config

docker pull karmagyz/mesos-flink:lastest

docker run -d  --net=host \
  --name mesos-master \
  --entrypoint ./mesos-1.9.0/build/bin/mesos-master.sh \
  -e MESOS_HOSTNAME=127.0.0.1 \
  -e MESOS_PORT=5050 \
  -e MESOS_QUORUM=1 \
  -e MESOS_REGISTRY=in_memory \
  -e MESOS_LOG_DIR=/var/log/mesos \
  -e MESOS_WORK_DIR=/var/tmp/mesos \
  -v "/var/log/mesos:/var/log/mesos" \
  -v "/var/tmp/mesos:/var/tmp/mesos" \
  karmagyz/mesos-flink

docker run -d --net=host \
  --name mesos-slave \
  --privileged \
  --entrypoint ./mesos-1.9.0/build/bin/mesos-slave.sh \
  -e MESOS_PORT=5051 \
  -e MESOS_MASTER=127.0.0.1:5050 \
  -e MESOS_SWITCH_USER=0 \
  -e MESOS_CONTAINERIZERS=docker,mesos \
  -e MESOS_LOG_DIR=/var/log/mesos \
  -e MESOS_WORK_DIR=/var/tmp/mesos \
  -e MESOS_SYSTEMD_ENABLE_SUPPORT=false \
  -v "/var/log/mesos-sl:/var/log/mesos" \
  -v "/var/tmp/mesos-sl:/var/tmp/mesos" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ${FLINK_HOME}:${FLINK_HOME} \
  -v /cgroup:/cgroup \
  -v /sys:/sys \
  -v /usr/local/bin/docker:/usr/local/bin/docker \
  karmagyz/mesos-flink