#!/bin/bash -e

if [ "$IOTCRAFTER_UPGRADE" = "1" ]; then
	on_chroot << EOF
apt-get -y update
apt-get -y --force-yes upgrade
EOF
fi

if [ "$IOTCRAFTER_RPI_UPDATE" = "1" ]; then
	on_chroot << EOF
mod_dirs=\$(ls /lib/modules)
mod_dirs_count=\$(ls /lib/modules|wc -w)

echo "Updating RPI firmware to rev: '$IOTCRAFTER_RPI_FIRMWARE_REV'.."
yes | rpi-update $IOTCRAFTER_RPI_FIRMWARE_REV

if [ \$? -eq 0 ]; then
	if [ -d /lib/modules.bak ]; then
		rm -rf /lib/modules.bak
	fi
	if [ -d /boot.bak ]; then
		rm -rf /boot.bak
	fi
	cur_mod_dirs_count=\$(ls /lib/modules|wc -w)
	if [ "\${mod_dirs_count}" = "2" -a "\${cur_mod_dirs_count}" = "4" ]; then
		echo "Removing old modules: \${mod_dirs}"
		(cd /lib/modules; rm -rf \${mod_dirs};)
	fi
fi
EOF
fi
