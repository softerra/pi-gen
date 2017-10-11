#!/bin/bash -e

# install init script
install -m 755 files/iotc_init.sh ${ROOTFS_DIR}/opt/iotc/bin/

# embed into RPi's first start script,
# which is /usr/lib/raspi-config/init_resize.sh,
# IOTC-specific setup:
#   insert a command making a copy of the data sector right before
#   variables check in the main() function of the script init_resize.sh
if [ -f ${ROOTFS_DIR}/usr/lib/raspi-config/init_resize.sh ] &&
	! grep -q '/opt/iotc/bin/iotc_init.sh' ${ROOTFS_DIR}/usr/lib/raspi-config/init_resize.sh; then
	sed -i '
			/^main\s*()/ {
				:fc
				N
				/check_variables/ !{
					b fc
				}
				:ff
				N
				/\s*fi\s*$/ !{
					b ff
				}
				/\s*fi\s*$/ {
					a\
\  /opt/iotc/bin/iotc_init.sh \$ROOT_DEV \$ROOT_PART_END
				}
}' ${ROOTFS_DIR}/usr/lib/raspi-config/init_resize.sh
	fi

# Enable UART as need
if [ ! -z "$IOTCRAFTER_ENABLE_UART" ]; then
	sed -r -i 's/^#?enable_uart=.*$/enable_uart='$IOTCRAFTER_ENABLE_UART'/' ${ROOTFS_DIR}/boot/config.txt
	grep -q '^enable_uart=' ${ROOTFS_DIR}/boot/config.txt || \
		echo "echo 'enable_uart='$IOTCRAFTER_ENABLE_UART >> ${ROOTFS_DIR}/boot/config.txt" | /bin/bash
fi

# prepare wlan0 interface configuration template in /etc/network/interfaces
#TODO: consider not doing this for 'upgrade' ?
interfaces=${ROOTFS_DIR}/etc/network/interfaces
echo "grep -Eq '^iface\s*wlan0\s*' $interfaces && \
	sed -i '
		/^iface\s*wlan0\s*/, /^\s*\$/ {
			/^iface\s*wlan0\s*/ {
				c\
iface wlan0 inet dhcp\\
\    wpa-ssid ssid\\
\    wpa-psk key
		}
		/^\s*\$/ {p}
		/^iface\s*wlan0\s*/ !{
			d
		}
	}' $interfaces || \
	cat >> $interfaces <<END

allow-hotplug wlan0
iface wlan0 inet dhcp
    wpa-ssid ssid
    wpa-psk key
END" | /bin/bash
