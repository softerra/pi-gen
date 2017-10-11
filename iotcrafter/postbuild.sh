#!/bin/bash

BUILD_RC=$1
echo ${BUILD_RC} > iotcrafter/build_rc

echo "Running Iotcrafter postbuild.sh script in $(pwd)"
if [ -f config ]; then
	source config
fi

# restore parent's ownership to the dirs: deploy, local kernel repo
chown -R --reference=. deploy kernel

echo "IOTCRAFTER_KERNEL_DIR=${IOTCRAFTER_KERNEL_DIR}"
if [ -n "${IOTCRAFTER_KERNEL_DIR}" ]; then
	chown -R --reference=. ${IOTCRAFTER_KERNEL_DIR}
fi
