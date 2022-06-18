#!/bin/bash

if ! which gcc ; then
	echo "gcc not found!"
	exit 1
fi

if ! gcc --version | grep "4.8.5" ; then
	echo "gcc version not 4.8.5, may not build ok!"
	exit 1
fi

if [ ! -f .config ] ; then
	make defconfig
fi

start_time=`date`
make clean
make bzImage -j`nproc`
ret=$?
end_time=`date`

echo "All done![${ret}]"
echo "  ${start_time}"
echo "  ${end_time}"
