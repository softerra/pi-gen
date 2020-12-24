#!/bin/bash -e

MIRROR=${RASPBIAN_REPO_MIRROR:-http://raspbian.raspberrypi.org/raspbian/}

if [ ! -d "${ROOTFS_DIR}" ]; then
	bootstrap ${RELEASE} "${ROOTFS_DIR}" ${MIRROR}
fi
