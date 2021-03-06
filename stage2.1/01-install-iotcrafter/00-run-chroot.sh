#!/bin/bash

#REQ_NODEV="v8.11.2"
REQ_NODEV_LATEST="v10"

if [ ! -v REQ_NODEV ]; then
	# exact version is preferrable, if not set - fall back on LATEST
	REQ_NODEV=`wget -O - http://nodejs.org/dist/latest-${REQ_NODEV_LATEST}.x/SHASUMS256.txt \
		| sed -n 's/^[^[:space:]]*[[:space:]]*node-\('${REQ_NODEV_LATEST}'[^-]*\)-.*$/\1/ p' \
		| head -n 1`
	echo "Installing latest nodejs ${REQ_NODEV_LATEST}.x: ${REQ_NODEV}"
else
	echo "Installing nodejs ${REQ_NODEV}"
fi

# need to remove and 'install' over
apt-get -y --force-yes remove nodejs
rm -f /usr/bin/node
cd /tmp
wget http://nodejs.org/dist/${REQ_NODEV}/node-${REQ_NODEV}-linux-armv6l.tar.xz

if [ -f node-${REQ_NODEV}-linux-armv6l.tar.xz ]; then
	tar xfJ node-${REQ_NODEV}-linux-armv6l.tar.xz
	cd node-${REQ_NODEV}-linux-armv6l
	cp -R * /usr/
	echo "Installed (copied) node-${REQ_NODEV}-linux-armv6l"
	cd ../
	rm -rf node-${REQ_NODEV}-linux-armv6l*

	# RUN under armv6l
	export QEMU_CPU=arm1176
	uname -a # check cpu
	npm config set unsafe-perm true
	echo "npm config set unsafe-perm done"
	#npm install bower -g
	npm install yarn -g
	echo "npm install yarn done"
	npm install npm@latest -g
	echo "npm install latest done"
else
	echo "Error: failed to get required nodejs node-${REQ_NODEV}-linux-armv6l.tar.xz"
	exit 1
fi
