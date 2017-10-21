#!/bin/bash -e

install -m 644 files/iotcrafter.list ${ROOTFS_DIR}/etc/apt/sources.list.d/

on_chroot << EOF
uname -a # check cpu

apt-get -y update
apt-get -y --force-yes install iotc-core iotc-ide

dpkg-reconfigure -fnoninteractive -plow unattended-upgrades
EOF
