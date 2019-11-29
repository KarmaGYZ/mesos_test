# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM ubuntu:16.04

# Install dependencies.
RUN apt-get update && \
    apt-get install -qy \
      autoconf \
      build-essential \
      clang \
      curl \
      git \
      iputils-ping \
      libapr1-dev \
      libcurl4-nss-dev \
      libev-dev \
      libevent-dev \
      libsasl2-dev \
      libssl-dev \
      libsvn-dev \
      libtool \
      maven \
      openjdk-8-jdk \
      python-dev \
      python-six \
      sed \
      software-properties-common \
      tar wget git \
      zlib1g-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists

# Install newer CMake.
RUN curl -sSL https://cmake.org/files/v3.8/cmake-3.8.2-Linux-x86_64.sh \
         -o /tmp/install-cmake.sh && \
    sh /tmp/install-cmake.sh --skip-license --prefix=/usr/local && \
    rm -f /tmp/install-cmake.sh

# Install Python 3.6.
RUN add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -qy \
      python3.6 \
      python3.6-dev \
      python3.6-venv && \
    add-apt-repository --remove -y ppa:deadsnakes/ppa && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists

RUN apt-get update && \
   apt-get install -qy apt-transport-https ca-certificates curl software-properties-common && \
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
   add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" && \
   apt-get update && \
   apt-get install -qy docker-ce  && \
   apt-get clean && \
    rm -rf /var/lib/apt/lists

RUN usermod -aG docker $(whoami) 

# Use update-alternatives to set python3.6 as python3.
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1

# Install pip for Python 3.6.
RUN curl https://bootstrap.pypa.io/get-pip.py | python3

COPY ["mesos-1.9.0.tar.gz", "mesos-1.9.0.tar.gz"]

RUN tar -zxf mesos-1.9.0.tar.gz


RUN cd mesos-1.9.0 && \
    mkdir build && \
    cd build && \
    ../configure && \
    make -j 4

RUN make install
