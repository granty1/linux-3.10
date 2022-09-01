#!/bin/bash

if [ -f /.dockerenv ]
then
	echo "can't fun this script in docker"
	exit 1
fi

docker build . -t linux3.10:latest
