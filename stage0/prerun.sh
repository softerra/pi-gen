#!/bin/bash -e

#MIRROR=http://raspbian.raspberrypi.org/raspbian/
MIRROR=http://debian.bio.lmu.de/raspbian/raspbian/
#MIRROR=http://mirror.netzwerge.de/raspbian/

if [ ! -d "${ROOTFS_DIR}" ]; then
	bootstrap ${RELEASE} "${ROOTFS_DIR}" ${MIRROR}
fi
