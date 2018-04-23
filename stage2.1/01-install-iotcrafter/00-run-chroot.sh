#!/bin/bash

REQ_NODEV="v6.14.1"

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
	npm install bower -g
else
	echo "Error: failed to get required nodejs node-${REQ_NODEV}-linux-armv6l.tar.xz"
	exit 1
fi
