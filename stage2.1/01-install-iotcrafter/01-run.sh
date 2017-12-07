#!/bin/bash -e

install -m 644 files/iotcrafter.list ${ROOTFS_DIR}/etc/apt/sources.list.d/
wget -qO - http://iotcrafter.com:8888/iotc/iotcrafter.gpg.key | apt-key add -

on_chroot << EOF
uname -a # check cpu

apt-get -y update

echo iotc iotc/cpuid string RPI | debconf-set-selections
#echo iotc iotc/kernvers string {kern_version} | debconf-set-selections
echo iotc iotc/load-overlays boolean false | debconf-set-selections

apt-get -y install iotc-core iotc-ide
dpkg-reconfigure -fnoninteractive -plow unattended-upgrades

# remove all iotc's settings
echo PURGE | debconf-communicate iotc
EOF
