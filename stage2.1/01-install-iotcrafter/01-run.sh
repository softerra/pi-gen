#!/bin/bash -e

install -m 644 files/iotcrafter.list ${ROOTFS_DIR}/etc/apt/sources.list.d/

on_chroot << EOF
uname -a # check cpu

apt-get -y update
echo iotc iotc/cpuid string RPI | debconf-set-selections
#echo iotc iotc/kernvers string {kern_version} | debconf-set-selections
apt-get -y --allow-unauthenticated install iotc-core iotc-ide

dpkg-reconfigure -fnoninteractive -plow unattended-upgrades
EOF
