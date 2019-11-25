#!/usr/bin/env bash

# Install Command Line Tools. The Command Line Tools from XCode >= 8.0 are required.
# xcode-select --install

# Install Homebrew.
# ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# Install Java.
# brew install Caskroom/cask/java


# Install libraries.
brew install wget git autoconf automake libtool subversion maven xz

# Install Python dependencies.
sudo easy_install pip
pip --user install virtualenv


curl -O http://mirror.bit.edu.cn/apache/mesos/1.9.0/mesos-1.9.0.tar.gz
tar -zxf mesos-1.9.0.tar.gz
cd mesos-1.9.0
mkdir build
cd build
../configure
make -j 4

# Start mesos
./bin/mesos-master.sh --ip=127.0.0.1 --work_dir=/var/lib/mesos &
./bin/mesos-agent.sh --master=127.0.0.1:5050 --work_dir=/var/lib/mesos &
