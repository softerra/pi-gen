#!/bin/bash

if [ "$ROOTFS_DIR" = '' ]; then
	echo "Error: Rootfs direcotry is required"
	exit 1
fi

MY_DIR=$(cd $(dirname $0); pwd)
IMG_DIR=${ROOTFS_DIR}
# ${IOTCRAFTER_KERNEL_DIR}
KERNEL_DIR=${BASE_DIR}/kernel

# $CROSS_PATH
CROSS_PREFIX=${CROSS_PREFIX:-arm-linux-gnueabihf-}
if [ "${CROSS_PATH}" != "" ]; then
	CROSS_PREFIX="${CROSS_PATH}/${CROSS_PREFIX}"
fi

KERNEL_GIT=https://github.com/raspberrypi/linux.git
KERNEL_HASH=${IOTCRAFTER_KERNEL_HASH}	# force to use the commit if specified, otherwise detect

LINUX_DIR=linux
BUILD_DIR=build
MODULES_DIR=modules
PI1_CONF=bcmrpi_defconfig
PI2_CONF=bcm2709_defconfig
CONFIG_M=(APDS9960 BH1750 BMP280 BMP085_I2C)
check_modules="iio/light/apds9960 iio/light/bh1750 iio/pressure/bmp280 iio/pressure/bmp280-i2c"
OVERLAYS="apds9960"

kernelName=
buildDir=
modulesDir=
modulesDirName=
defConfig=
piMakeOpts=

CHECK_MSG=
INFO_MSG=

MAKE_OPTS="-C ${KERNEL_DIR}/${LINUX_DIR} ARCH=arm CROSS_COMPILE=${CROSS_PREFIX}"

if [ "${KERNEL_DIR}" = "${KERNEL_DIR%%/kernel}" ]; then
	# seach for 'rm -rf'
	echo "KERNEL_DIR must end with '/kernel'"
	exit 1
fi

# Detrmine kernel GIT version
# - check wether firmware is rpi-update'd
getKernelHash()
{
	local fw_hash=''
	local kern_hash=''

	if [ -f $IMG_DIR/boot/.firmware_revision ]; then
		fw_hash=$(cat $IMG_DIR/boot/.firmware_revision)
		kern_hash=$(wget https://raw.github.com/Hexxeh/rpi-firmware/$fw_hash/git_hash -O -)
		echo -e "Detected (rpi-update):\nFW hash=$fw_hash\nkern_hash=$kern_hash"
	else
		fw_hash=$(zgrep "* firmware as of" $IMG_DIR/usr/share/doc/raspberrypi-bootloader/changelog.Debian.gz | head -1 | awk '{ print $5 }')
		kern_hash=$(wget https://raw.github.com/raspberrypi/firmware/$fw_hash/extra/git_hash -O -)
		echo -e "Detected:\nFW hash=$fw_hash\nkern_hash=$kern_hash"
	fi

	if [ ${#kern_hash} -ne 40 ]; then
		echo "Warn: got kernel hash is no 40 chars!"
	fi
	if [ "$KERNEL_HASH" != "" ]; then
		if [ "$kern_hash" != "$KERNEL_HASH" ]; then
			echo "Warn: updating to different kernel: $KERNEL_HASH"
		fi
		return
	fi
	KERNEL_HASH=$kern_hash
}

# lock and wait kernel directory to share local kernel repo
# between possible different parallel builds
lockDir()
{
	try=25
	wait_sec=5

	echo -n "locking $1: "
	while [ $try -gt 0 ]; do
		mkdir $1/.lock 2>/dev/null
		[ $? -eq 0 ] && echo "$$: Locked" && echo $$ > $1/.lock/pid && return 0

		pid=$(cat $1/.lock/pid 2>/dev/null)
		ps $pid > /dev/null 2>&1
		[ $? -ne 0 ] && unlockDir $1 && continue

		echo -n "."
		sleep $wait_sec
		try=$((try -1))
	done
	echo "failed: another process still locking it"
	return 1
}

unlockDir()
{
	if [ "$1" != "" ]; then
		rm $1/.lock/pid 2>/dev/null
		rmdir $1/.lock 2>/dev/null
	fi
	echo "$$: Unlocked"
}

fixDirPermissions()
{
	local parent=$(dirname $1)
	chown -R --reference=$parent $1
}

prepareKernelDir()
{
	local rc=0

	# Do not re-clone kernel sources, do not rebuild kernel if only
	## - this is not requested explicitly
	## - requested revision is not the one currently checked out
	if [ "${IOTCRAFTER_KERNEL_REBUILD}" = "0" -a -d $KERNEL_DIR/$LINUX_DIR ]; then
		local head_hash=$(cd $KERNEL_DIR/$LINUX_DIR; git rev-parse --verify HEAD)
		if [ "$head_hash" == "$KERNEL_HASH" ]; then
			## - kenerl sources don't have changes
			#local no_rebuild=$(cd $KERNEL_DIR/$LINUX_DIR; \
			#					git status --porcelain | grep -Eq '^\s?[MD]\s*\w+'; \
			#					echo $?)
			#[ $no_rebuild -eq 1 ] && echo "No need to update kernel sources" && return 0
			echo "No need to update kernel sources"
			return 0
		fi
	fi

	echo "(Re)Build kernel"
	rm -rf $KERNEL_DIR
	mkdir -p $KERNEL_DIR

	if [ "${IOTCRAFTER_KERNEL_DIR}" != "" ]; then
		rc=1
		if [ ! -d "${IOTCRAFTER_KERNEL_DIR}/$LINUX_DIR" ]; then # IOTCRAFTER_KERNEL_DIR && !IOTCRAFTER_KERNEL_DIR/LINUX_DIR
			mkdir -p ${IOTCRAFTER_KERNEL_DIR}
			if lockDir ${IOTCRAFTER_KERNEL_DIR}; then
				echo "Cloning to local common repo"
				git clone $KERNEL_GIT ${IOTCRAFTER_KERNEL_DIR}/$LINUX_DIR
				rc=$?
				fixDirPermissions ${IOTCRAFTER_KERNEL_DIR}
				unlockDir ${IOTCRAFTER_KERNEL_DIR}
			fi
			[ $rc -ne 0 ] && echo "Error: Cloning kernel repo to local failed" && return 1
		else													# IOTCRAFTER_KERNEL_DIR && IOTCRAFTER_KERNEL_DIR/LINUX_DIR
			if lockDir ${IOTCRAFTER_KERNEL_DIR}; then
				echo "Fetching to local common repo"
				(cd ${IOTCRAFTER_KERNEL_DIR}/$LINUX_DIR && git fetch)
				rc=$?
				fixDirPermissions ${IOTCRAFTER_KERNEL_DIR}
				unlockDir ${IOTCRAFTER_KERNEL_DIR}
			fi
			[ $rc -ne 0 ] && echo "Error: Fetching kernel sources to local failed" && return 1
		fi

		rc=1
		if lockDir ${IOTCRAFTER_KERNEL_DIR}; then
			echo "Checkout from local repo and clone to build dir"
			(cd ${IOTCRAFTER_KERNEL_DIR}/$LINUX_DIR \
				&& git clean -f \
				&& git checkout -- * \
				&& git checkout $KERNEL_HASH \
				&& git clone --depth 1 --no-local ${IOTCRAFTER_KERNEL_DIR}/$LINUX_DIR $KERNEL_DIR/$LINUX_DIR)
			rc=$?
			fixDirPermissions ${IOTCRAFTER_KERNEL_DIR}
			unlockDir ${IOTCRAFTER_KERNEL_DIR}
		fi
		[ $rc -ne 0 ] && echo "Error: Clone local repo and checkout $KERNEL_HASH failed" && return 1

	else # IOTCRAFTER_KERNEL_DIR=""
		# completely local repo
		git clone $KERNEL_GIT $KERNEL_DIR/$LINUX_DIR
		[ $? -ne 0 ] && echo "Error: Cloning kernel repo failed" && return 1

		echo "Checking out: $KERNEL_HASH"
		(cd $KERNEL_DIR/$LINUX_DIR && git checkout $KERNEL_HASH)
		[ $? -ne 0 ] && echo "Error: Checkout $KERNEL_HASH failed" && return 1
	fi

	return 0
}

# Set params for PI <N>
# $1 = N
selectPI()
{
	if [ $1 -eq 1 ]; then
		kernelName=kernel
		buildDir=$KERNEL_DIR/$BUILD_DIR
		modulesDir=$KERNEL_DIR/$MODULES_DIR
		defConfig=$PI1_CONF
	else
		kernelName=kernel7
		buildDir=$KERNEL_DIR/${BUILD_DIR}7
		modulesDir=$KERNEL_DIR/${MODULES_DIR}7
		defConfig=$PI2_CONF
	fi

	piMakeOpts="O=${buildDir} INSTALL_MOD_PATH=${modulesDir}"

	#NOTE: the value is available only after make modules_install
	modulesDirName=$(ls $modulesDir/lib/modules)
}

# $1 = 1|2 (PI1 or PI2)
makeDefConf()
{
	selectPI $1
	if [ ! -f $buildDir/.config ]; then
		echo "Making defconfig for PI$1"
		make $MAKE_OPTS $piMakeOpts $defConfig
	else
		echo "No need of defconfig for PI$1"
	fi
}

# $1 = 1|2 (PI1 or PI2)
enableModules()
{
	selectPI $1

	addmods=${CONFIG_M[*]}
	addmods=${addmods// /|}
	grep -E '^#[[:space:]]*CONFIG_('$addmods').*$' ${buildDir}/.config
	if [ $? -eq 0 ]; then
		echo "Turning on the defined modules to be compiled for PI$1"
		sed -ri 's/^#[[:space:]]*CONFIG_('$addmods').*$/CONFIG_\1=m/' ${buildDir}/.config

		make $MAKE_OPTS $piMakeOpts oldconfig
	else
		echo "Nothing to re-config for PI$1"
	fi
}

addOverlays()
{
	local overlayDir=$MY_DIR/overlays
	local targetOverlayDir=$KERNEL_DIR/$LINUX_DIR/arch/arm/boot/dts/overlays

	for overlay in $OVERLAYS; do
		echo "Adding overlay ${overlay}"
		cp $overlayDir/${overlay}-overlay.dts $targetOverlayDir/

		if grep -E 'RPI_DT_OVERLAYS=y' $targetOverlayDir/Makefile; then
			# old way
			if ! grep -E '^dtbo-[^=]*=\s*'${overlay}'\.' $targetOverlayDir/Makefile; then
				echo "Adding overlay ${overlay} to compilation"
				sed -i '/^dtbo-\$[^=]*=/, /^\s*$/ {
							/^\s*$/ {
								i\
dtbo-$(RPI_DT_OVERLAYS) += '${overlay}'.dtbo
							}
					}' $targetOverlayDir/Makefile
			fi
		else
			# new way
			if ! grep -E '^\s*'${overlay}'\.dtbo\s*\\$' $targetOverlayDir/Makefile; then
				sed -i '/^dtbo-\$(CONFIG_ARCH_BCM2835)\s*+=\s*\\/ {
					a\
	'${overlay}'.dtbo \\
					}' $targetOverlayDir/Makefile
			fi
		fi
	done
}

# $1 = 1|2 (PI1 or PI2)
makeAll()
{
	echo "`date`: Start building kernel and modules for $1"
	selectPI $1

	make -j8 $MAKE_OPTS $piMakeOpts && \
		make -j8 $MAKE_OPTS $piMakeOpts modules_install
	local rc=$?
	echo "`date`: Done building kernel and modules for $1 (rc=$rc)"

	INFO_MSG="RPi $1 build cmd: make $MAKE_OPTS $piMakeOpts\n${INFO_MSG}"

	# check whether additional/required overlays and modules were built
	selectPI $1		# for correct modulesDirName value
	for overlay in $OVERLAYS; do
		if [ ! -f $buildDir/arch/arm/boot/dts/overlays/${overlay}.dtbo ]; then
			CHECK_MSG="Err:overlay:$buildDir/arch/arm/boot/dts/overlays/${overlay}.dtbo\n${CHECK_MSG}"
		fi
	done
	for mod_path in $check_modules; do
		if [ ! -f $modulesDir/lib/modules/$modulesDirName/kernel/drivers/${mod_path}.ko ]; then
			CHECK_MSG="Err:module:$modulesDir/lib/modules/$modulesDirName/kernel/drivers/${mod_path}.ko\n${CHECK_MSG}"
		fi
	done

	return $rc
}

# $1 = 1|2 (PI1 or PI2)
installAll()
{
	selectPI $1

#	# For now just subst modules, dtbs and overlays
	echo "Installing modules (to $modulesDirName), dtbs and overlays for $1"
#	rm -f $IMG_DIR/boot/overlays/*
	# copy once
	if [ $1 -eq 1 ]; then
		# dtbs
		cp -f $buildDir/arch/arm/boot/dts/*.dtb $IMG_DIR/boot/
		cp -f $buildDir/arch/arm/boot/dts/overlays/*.dtb* $IMG_DIR/boot/overlays/

		# README
		cp $KERNEL_DIR/$LINUX_DIR/arch/arm/boot/dts/overlays/README $IMG_DIR/boot/overlays/
	fi

	# kernel
	cp $IMG_DIR/boot/$kernelName.img $IMG_DIR/boot/$kernelName-backup.img
	cp $buildDir/arch/arm/boot/zImage $IMG_DIR/boot/$kernelName.img

	# modules
	rm -rf $IMG_DIR/lib/modules/$modulesDirName
	cp -R --no-dereference $modulesDir/lib/modules/$modulesDirName $IMG_DIR/lib/modules/
	rm $IMG_DIR/lib/modules/$modulesDirName/build $IMG_DIR/lib/modules/$modulesDirName/source
}

getKernelHash
prepareKernelDir || exit 1
makeDefConf 1 || exit 1
makeDefConf 2 || exit 1
enableModules 1 || exit 1
enableModules 2 || exit 1
addOverlays
makeAll 1 || exit 1
makeAll 2 || exit 1
INFO_MSG="${INFO_MSG}\nGet headers: use INSTALL_HDR_PATH with headers_install"
installAll 1
installAll 2

if [ ! -z "$CHECK_MSG" ]; then
	echo -e "$CHECK_MSG"
fi
if [ ! -z "$INFO_MSG" ]; then
	echo -e "$INFO_MSG"
fi

exit 0
