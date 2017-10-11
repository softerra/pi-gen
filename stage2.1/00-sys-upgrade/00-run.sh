#!/bin/bash -e

if [ "$IOTCRAFTER_UPGRADE" = "1" ]; then
	on_chroot << EOF
apt-get -y update
apt-get -y --force-yes upgrade
EOF
fi

if [ "$IOTCRAFTER_RPI_UPDATE" = "1" ]; then
	on_chroot << EOF
rpi-update
if [ \$? -eq 0 ]; then
	if [ -d /lib/modules.bak ]; then
		rm -rf /lib/modules.bak
	fi
	if [ -d /boot.bak ]; then
		rm -rf /boot.bak
	fi
fi
EOF
fi
