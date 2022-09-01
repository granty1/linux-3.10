#!/bin/bash

docker run -d --privileged \
	-v `pwd`:/data \
	-v /dev:/dev \
	--name linux-3.10 \
	linux3.10:latest /sbin/init
