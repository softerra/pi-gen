#!/bin/bash

if [ "$ROOTFS_DIR" = '' ]; then
	echo "Error: Rootfs direcotry is required"
	exit 1
fi

MY_DIR=$(cd $(dirname $0); pwd)
IMG_DIR=${ROOTFS_DIR}
# ${IOTCRAFTER_KERNEL_DIR}
KERNEL_DIR=${BASE_DIR}/kernel

KERNEL_GIT=https://github.com/raspberrypi/linux.git
KERNEL_HASH=${IOTCRAFTER_KERNEL_HASH}	# force to use the commit if specified, otherwise detect

LINUX_DIR=linux
BUILD_DIR=build
MODULES_DIR=modules

CONFIG_M=(APDS9960 BH1750 BMP280 BMP085_I2C SI7020)
check_modules="iio/light/apds9960 iio/light/bh1750 iio/pressure/bmp280 iio/pressure/bmp280-i2c iio/humidity/si7020"
OVERLAYS="apds9960"

# kernels to build
KERNEL_LIST="kernel kernel7 kernel7l kernel8"

KERNEL_ARCH_kernel="arm"
KERNEL_ARCH_kernel7="arm"
KERNEL_ARCH_kernel7l="arm"
KERNEL_ARCH_kernel8="arm64"

KERNEL_CONF_kernel="bcmrpi_defconfig"
KERNEL_CONF_kernel7="bcm2709_defconfig"
KERNEL_CONF_kernel7l="bcm2711_defconfig"
KERNEL_CONF_kernel8="bcm2711_defconfig"

KERNEL_CROSS_arm="arm-linux-gnueabihf-"
KERNEL_CROSS_arm64="aarch64-linux-gnu-"

# global build vars
kernelName=
kernelDir=
kernelArch=
defConfig=
crossPrefix=
buildDir=
modulesDir=
modulesDirName=
piMakeOpts=
CROSS_PREFIX=
#kernelHeadersDir=
MAKE_OPTS="-C ${KERNEL_DIR}/${LINUX_DIR} ARCH=arm CROSS_COMPILE=${CROSS_PREFIX}"

CHECK_MSG=
INFO_MSG=

# $1 kernel name from the KERNEL_LIST
selectKernel()
{
	kernelName=$1

	kernelDir=${KERNEL_DIR}/${kernelName}
	buildDir=${kernelDir}/${BUILD_DIR}
	modulesDir=${kernelDir}/${MODULES_DIR}
	piMakeOpts="O=${buildDir} INSTALL_MOD_PATH=${modulesDir}"
	#kernelHeadersDir=${KERNEL_DIR}/kernel-headers/${KERNEL_HASH}
	#piMakeOpts="O=${buildDir} INSTALL_MOD_PATH=${modulesDir} INSTALL_HDR_PATH=${kernelHeadersDir}"

	eval "kernelArch=\$KERNEL_ARCH_${kernelName}"
	eval "defConfig=\$KERNEL_CONF_${kernelName}"
	eval "crossPrefix=\$KERNEL_CROSS_${kernelArch}"

	if [ "${CROSS_PATH}" == "" ]; then
		CROSS_PREFIX=${crossPrefix}
	else
		CROSS_PREFIX="${CROSS_PATH}/${crossPrefix}"
	fi
	MAKE_OPTS="-C ${KERNEL_DIR}/${LINUX_DIR} ARCH=${kernelArch} CROSS_COMPILE=${CROSS_PREFIX}"

	#NOTE: the value is available only after make modules_install
	modulesDirName=$(ls $modulesDir/lib/modules)
}

#===============================================================================
if [ "${KERNEL_DIR}" = "${KERNEL_DIR%%/kernel}" ]; then
	# seach for 'rm -rf'
	echo "KERNEL_DIR must end with '/kernel'"
	exit 1
fi

#===============================================================================
# Determine kernel GIT version
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
		fw_hash=$(zgrep "* firmware as of" $IMG_DIR/usr/share/doc/raspberrypi-bootloader/changelog.Debian.gz \
					| head -1 \
					| sed  -n 's|.* \([^ ]*\)$|\1|p')
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
			(cd $KERNEL_DIR/$LINUX_DIR && git reset --hard)
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
#===============================================================================

# $1 = kernel name from the KERNEL_LIST
makeDefConf()
{
	selectKernel $1
	if [ ! -f $buildDir/.config ]; then
		echo "Making defconfig for kernel: $1"
		make $MAKE_OPTS $piMakeOpts $defConfig
	else
		echo "No need of defconfig for kernel: $1"
	fi
}

# $1 = kernel name from the KERNEL_LIST
enableModules()
{
	selectKernel $1

	addmods=${CONFIG_M[*]}
	addmods=${addmods// /|}
	grep -E '^#[[:space:]]*CONFIG_('$addmods').*$' ${buildDir}/.config
	if [ $? -eq 0 ]; then
		echo "Turning on the defined modules to be compiled for kernel: $1"
		sed -ri 's/^#[[:space:]]*CONFIG_('$addmods').*$/CONFIG_\1=m/' ${buildDir}/.config

		make $MAKE_OPTS $piMakeOpts oldconfig
	else
		echo "Nothing to re-config for kernel: $1"
	fi
}

patchSources()
{
	local patchesDir=$MY_DIR/patches

	for p in $(ls $patchesDir); do
		patch -d $KERNEL_DIR/$LINUX_DIR -p1 < $patchesDir/$p
	done
}

addOverlays()
{
	local overlayDir=$MY_DIR/overlays
	local targetOverlayDir=$KERNEL_DIR/$LINUX_DIR/arch/${kernelArch}/boot/dts/overlays

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

# $1 = kernel name from the KERNEL_LIST
makeAll()
{
	echo "`date`: Start building kernel, modules and packages for kernel: $1"
	selectKernel $1

	# and '&& headers_install' if need
	make -j8 $MAKE_OPTS $piMakeOpts && \
		make -j8 $MAKE_OPTS $piMakeOpts modules_install && \
		make -j8 $MAKE_OPTS $piMakeOpts bindeb-pkg
	local rc=$?
	echo "`date`: Done building kernel, modules and packages for kernel: $1 (rc=$rc)"

	INFO_MSG="Kernel '$1' build cmd: make $MAKE_OPTS $piMakeOpts\n${INFO_MSG}"

	# check whether additional/required overlays and modules were built
	selectKernel $1		# for correct modulesDirName value
	for overlay in $OVERLAYS; do
		if [ ! -f $buildDir/arch/${kernelArch}/boot/dts/overlays/${overlay}.dtbo ]; then
			CHECK_MSG="Err:overlay:$buildDir/arch/${kernelArch}/boot/dts/overlays/${overlay}.dtbo\n${CHECK_MSG}"
		fi
	done
	for mod_path in $check_modules; do
		if [ ! -f $modulesDir/lib/modules/$modulesDirName/kernel/drivers/${mod_path}.ko ]; then
			CHECK_MSG="Err:module:$modulesDir/lib/modules/$modulesDirName/kernel/drivers/${mod_path}.ko\n${CHECK_MSG}"
		fi
	done

	return $rc
}

. $MY_DIR/linux-version

IOTC_MODULES="HCSR04"
IOTC_REPO_HCSR04="https://github.com/softerra/linux-hc-sro4.git"

get_kernel_version()
{
	local vars=`cat $KERNEL_DIR/linux/Makefile | \
					grep -E "^(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION) =" | \
						sed 's/ //g' | sed 's/^\(.*\)/local \\1/'`
	eval "$vars"

#	VERSION=4
#	PATCHLEVEL=2
#	SUBLEVEL=0
#	EXTRAVERSION=-rc1

	eval "$1=${VERSION}.${PATCHLEVEL}.${SUBLEVEL}$EXTRAVERSION"
}

# Checkout:
# - if repsective var IOTC_REPO_XXX_REV is defined, use it
# - if tags linux-vX.Y.Z defined, select the biggest version but not more than version of the current kernel
# - otherwise use default revision after cloning
prepareExtra()
{
	get_kernel_version kernel_version
	echo "preparing extra modules for kernel: $kernel_version"

	for m in $IOTC_MODULES; do
		# clenup
		rm -rf $KERNEL_DIR/iotc/$m
		# setup
		#mkdir -p $KERNEL_DIR/iotc/$m
		eval "repoUrl=\$IOTC_REPO_${m}"
		eval "repoRev=\$IOTC_REPO_${m}_REV"

		git clone $repoUrl $KERNEL_DIR/iotc/$m

		if [ "$repoRev" != "" ]; then
			(cd $KERNEL_DIR/iotc/$m
				git checkout $repoRev
			)
		else
			(cd $KERNEL_DIR/iotc/$m
				versions="$(git tag -l linux-v[0-9]* | sed 's/^linux-v//')"
				lxver_get_matched_version $kernel_version "$versions" "checkout_version"
				#echo "->checkout_version=$checkout_version"
				if [ "$checkout_version" != "0.0" ]; then
					checkout_version="linux-v${checkout_version}"
					echo "checkout ${checkout_version}"
					git checkout ${checkout_version}
				else
					echo "no special version to check out"
				fi
			)
		fi
	done
}

# $1 = kernel name from the KERNEL_LIST
makeExtra()
{
	echo "`date`: Start building extra modules for kernel: $1"
	selectKernel $1

	for d in $IOTC_MODULES; do
		cd $KERNEL_DIR/iotc/$d
		make $MAKE_OPTS $piMakeOpts M=$PWD clean
		make -j8 $MAKE_OPTS $piMakeOpts M=$PWD modules && \
			make -j8 $MAKE_OPTS $piMakeOpts M=$PWD modules_install
		cd ..
	done
}

cleanupModules()
{
	rm -rf $IMG_DIR/lib/modules/*
}

# install some items (e.g. dtbs) once
installed_dtbs=0
# $1 = kernel name from the KERNEL_LIST
installAll()
{
	selectKernel $1

#	# For now just subst modules, dtbs and overlays
	echo "Installing modules (to ${modulesDirName}), dtbs and overlays for kernel: $1"
#	rm -f $IMG_DIR/boot/overlays/*
	# once (from first 'arm' arch)
	if [ ${installed_dtbs} -eq 0 ]; then
		installed_dtbs=1
		# dtbs
		cp -f ${buildDir}/arch/${kernelArch}/boot/dts/*.dtb ${IMG_DIR}/boot/
		cp -f ${buildDir}/arch/${kernelArch}/boot/dts/overlays/*.dtb* ${IMG_DIR}/boot/overlays/

		# README
		cp -f ${KERNEL_DIR}/${LINUX_DIR}/arch/${kernelArch}/boot/dts/overlays/README ${IMG_DIR}/boot/overlays/
	fi

	# kernel
	#cp -f ${IMG_DIR}/boot/${kernelName}.img ${IMG_DIR}/boot/${kernelName}-backup.img
	if [ $kernelArch == "arm64" ]; then
		cp -f ${buildDir}/arch/arm64/boot/Image.gz ${IMG_DIR}/boot/${kernelName}.img
	else
		cp -f ${buildDir}/arch/arm/boot/zImage ${IMG_DIR}/boot/${kernelName}.img
	fi

	# modules
	#rm -rf $IMG_DIR/lib/modules/$modulesDirName
	cp -R --no-dereference ${modulesDir}/lib/modules/${modulesDirName} ${IMG_DIR}/lib/modules/
	rm -f ${IMG_DIR}/lib/modules/${modulesDirName}/build ${IMG_DIR}/lib/modules/${modulesDirName}/source

	# deploy kernel debs
	debDir=${DEPLOY_DIR}/${IMG_DATE}-${IMG_NAME}-deb
	mkdir -p ${debDir}
	cp -f ${kernelDir}/*.deb ${debDir}
}

getKernelHash
prepareKernelDir || exit 1

# make defconfigs, enable modules in the configs
for kern in ${KERNEL_LIST}; do
	makeDefConf ${kern} || exit 1
	enableModules ${kern} || exit 1
done
patchSources || exit 1
# overlays for arm64 is reference for arm
addOverlays

for kern in ${KERNEL_LIST}; do
	makeAll ${kern} || exit 1
done
INFO_MSG="${INFO_MSG}\nGet headers: use INSTALL_HDR_PATH with headers_install"
prepareExtra || exit 1

for kern in ${KERNEL_LIST}; do
	makeExtra ${kern} || exit 1
done

cleanupModules || exit 1

for kern in ${KERNEL_LIST}; do
	installAll ${kern}
done

if [ ! -z "${CHECK_MSG}" ]; then
	echo -e "${CHECK_MSG}"
fi
if [ ! -z "{$INFO_MSG}" ]; then
	echo -e "${INFO_MSG}"
fi

exit 0
