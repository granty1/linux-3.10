#!/bin/bash

WORKDIR=$(pwd)
JOBCOUNT=$(nproc)
export ARCH=x86
export INSTALL_PATH=${WORKDIR}/rootfs_debian_i386/boot/
export INSTALL_MOD_PATH=${WORKDIR}/rootfs_debian_i386/
export INSTALL_HDR_PATH=${WORKDIR}/rootfs_debian_i386/usr/

KERNEL_BUILD=${WORKDIR}/rootfs_debian_i386/usr/src/linux/
ROOTFS_PATH=${WORKDIR}/rootfs_debian_i386
OUTPUTDIR=${WORKDIR}/build_output/${ARCH}
ROOTFS_IMAGE=${OUTPUTDIR}/rootfs_debian_i386.ext3
KERNEL_IMAGE=${OUTPUTDIR}/bzImage

rootfs_size=1024

SMP="-smp 4"

usage() {
	echo "Usage: $0 [arg]"
	echo "  build_kernel: build the kernel image."
	echo "  build_rootfs: build the rootfs image."
	echo "  run: startup kernel with debian rootfs."
	echo "  rebuild_rootfs: repacked ext3 rootfs."
	echo "  onekey: build kernel and rootfs, just run up."
	echo "  run debug: enable gdb debug server."
	exit
}
if [ $# -lt 1 ]
then
	usage
fi

if [ $# -eq 2 ] && [ "$2" == "debug" ]
then
	echo "Enable qemu debug server"
	# -s : shorthand for -gdb tcp::1234
	# -S : freeze CPU at startup (use 'c' to start execution)
	DBG="-s -S"
	SMP=""
fi

if [ ! -d "${OUTPUTDIR}" ]
then
	mkdir -p "${OUTPUTDIR}"
fi

clean() {
	umount "${ROOTFS_IMAGE}" &> /dev/null 
	echo "Clean done!"
}

make_kernel_image(){
	if [ ! -f /.dockerenv ]
	then
		echo "must run in docker!"
		exit 1
	fi
	echo "start build kernel image..."
	make mrproper
	make  ARCH=i386  debian_i386_defconfig
	ls -alh .config
	if which bear &> /dev/null
	then
		bear make  ARCH=i386  -j "${JOBCOUNT}"
	else 
		make -j "${JOBCOUNT}"
	fi
	ret=$?
	echo "kernel build done![${ret}]"
	if [ "${ret}" != "0" ]
	then
		echo "Build failed!"
		clean && exit 1
	fi
	if [ -f arch/x86/boot/bzImage ]
	then
		cp -a arch/x86/boot/bzImage "${KERNEL_IMAGE}"
		[ -f System.map ] && cp -a System.map "${OUTPUTDIR}"
		[ -f vmlinux ] && cp -a vmlinux "${OUTPUTDIR}"
		chmod 644 "${KERNEL_IMAGE}"
		ls -alh "${KERNEL_IMAGE}"
		which file &> /dev/null && file "${KERNEL_IMAGE}"
	else
		echo "${KERNEL_IMAGE} not found!"
		clean && exit 1
	fi
}

prepare_rootfs(){
	if [ ! -d "${ROOTFS_PATH}" ]
	then
		echo "decompressing rootfs..."
		if [ ! -f rootfs_debian_i386.tar.gz ]
		then
			echo "fatal err! rootfs_debian_i386.tar.gz not found!"
			clean && exit 1
		fi
		if  ! tar -xf rootfs_debian_i386.tar.gz
		then
			 echo "unpack rootfs_debian_i386.tar.gz failed!"
			 clean && exit 1
		fi
	fi
	# clean mount
	#echo "" > "${ROOTFS_PATH}/etc/fstab" || true
	# clean motd
	#echo "" > "${ROOTFS_PATH}/etc/motd" || true
	#  root/linux
	sed -i '1s#.*#root:$6$jFcaO798$gCSHZGAfpuWEAyO00ZlWzy1JLygVteL/e8oSm00nY7/gWTtk.xjb33kVaSLcERWGyByAd3T25Ih.iY9FLM0SJ/:19217:0:99999:7:::#'  "${ROOTFS_PATH}/etc/shadow"
	echo "set user/passwd root/linux"
	# hostname = linux3-x86
	echo "linux3-x86" > "${ROOTFS_PATH}/etc/hostname"
	echo "set hostname linux3-x86"
}


build_kernel_devel(){
	kernver="$(make -s kernelrelease)"
	echo "kernel version: $kernver"

	mkdir -p "${KERNEL_BUILD}"
	cp -a include "${KERNEL_BUILD}"
	cp Makefile .config Module.symvers System.map "${KERNEL_BUILD}"
	mkdir -p "${KERNEL_BUILD}/arch/x86/"
	mkdir -p "${KERNEL_BUILD}/arch/x86/kernel/"
	mkdir -p "${KERNEL_BUILD}/scripts"

	cp -a arch/x86/include "${KERNEL_BUILD}/arch/x86/"
	cp -a arch/x86/Makefile "${KERNEL_BUILD}/arch/x86/"
	cp scripts/gcc-goto.sh "${KERNEL_BUILD}/scripts"
	cp -a scripts/Makefile.*  "${KERNEL_BUILD}/scripts"
	#cp arch/x86/kernel/module.lds "${KERNEL_BUILD}/arch/x86/kernel/"
	if [ ! -d "${WORKDIR}/rootfs_debian_i386/lib/modules/${kernver}" ]
	then
		mkdir -p "${WORKDIR}/rootfs_debian_i386/lib/modules/${kernver}"
	fi
	rm -f "${WORKDIR}/rootfs_debian_i386/lib/modules/${kernver}/build"
	ln -svf /usr/src/linux "${WORKDIR}/rootfs_debian_i386/lib/modules/${kernver}/build"
}

check_root(){
	if [ "$(id -u)" != "0" ]
	then
		echo "superuser privileges are required to run"
		echo "sudo ./run_debian_x86.sh build_rootfs"
		clean && exit 1
	fi
}

build_rootfs(){
	make install
	make modules_install -j "${JOBCOUNT}"
	#make headers_install

	build_kernel_devel

	echo "making image..."
	dd if=/dev/zero of="${ROOTFS_IMAGE}" bs=1M count=${rootfs_size}
	mkfs.ext3 -F "${ROOTFS_IMAGE}"
	mkdir -p "${OUTPUTDIR}/tmpmount"
	mount -t ext3 "${ROOTFS_IMAGE}" "${OUTPUTDIR}/tmpmount" -o loop
	echo "copy data into rootfs..."
	cp -a rootfs_debian_i386/* "${OUTPUTDIR}/tmpmount/"
	umount -f "${OUTPUTDIR}/tmpmount"
	sync
	rmdir "${OUTPUTDIR}/tmpmount" &> /dev/null || ls "${OUTPUTDIR}/tmpmount"
	chmod 644 "${ROOTFS_IMAGE}"
	ls -alh "${ROOTFS_IMAGE}"
}

run_qemu_debian(){
	if [ -f /.dockerenv ]
	then
		echo "must not run in docker!"
		exit 1
	fi
	QEMU_APP="qemu-system-i386"
	if ! which qemu-system-i386 &> /dev/null
	then
		if [ -f /usr/libexec/qemu-kvm ]
		then
			QEMU_APP="/usr/libexec/qemu-kvm"
		else
			echo "qemu-system-i386 or /usr/libexec/qemu-kvm not found!"
			clean && exit 1
		fi
	fi
	set -x

	${QEMU_APP} \
		-cpu kvm32 \
		-m 2048 \
		-nographic ${SMP} ${DBG} \
		-kernel "${KERNEL_IMAGE}" \
		-append "root=/dev/vda rw rootfstype=ext3 console=ttyS0 init=/sbin/init " \
		-drive if=none,file="${ROOTFS_IMAGE}",id=hd0 \
	 	-device virtio-blk-pci,drive=hd0 \
		-netdev user,id=mynet \
		-device virtio-net-pci,netdev=mynet

	ret=$?
	{ set +x; } 2>/dev/null;
	if [ "${ret}" != "0" ]
	then
		echo "Exit with err [${ret}]"
		exit
	fi
}

case $1 in
	build_kernel)
		make_kernel_image
		;;
	build_rootfs)
		check_root
		prepare_rootfs
		build_rootfs
		;;
	rebuild_rootfs)
		if [ -d "${ROOTFS_PATH}" ]
		then
			echo "clean ${ROOTFS_PATH}"
			rm -rf "${ROOTFS_PATH}"
		fi
		if [ -f "${ROOTFS_IMAGE}" ]
		then
			echo "clean ${ROOTFS_IMAGE}"
			rm -rf "${ROOTFS_IMAGE}"
		fi
		check_root
		prepare_rootfs
		build_rootfs
		;;
	run)
		if [ ! -f "${KERNEL_IMAGE}" ]
		then
			echo "canot find kernel image in ${KERNEL_IMAGE}, pls run build_kernel command firstly!!"
			echo "./run_debian_i386.sh build_kernel"
			clean && exit 1
		fi
		echo "using ${KERNEL_IMAGE}"
		if [ ! -f "${ROOTFS_IMAGE}" ]
		then
			echo "canot find rootfs image ${ROOTFS_IMAGE}, pls run build_rootfs command firstly!!"
			echo "sudo ./run_debian_i386.sh build_rootfs"
			clean && exit 1
		fi
		echo "using ${ROOTFS_IMAGE}"
		run_qemu_debian
		;;
	onekey)
		check_root
		make_kernel_image
		if [ -d rootfs_debian_i386 ]
		then
			echo "clean rootfs_debian_i386"
			rm -rf rootfs_debian_i386
		fi
		if [ -f rootfs_debian_i386.ext3 ]
		then
			echo "clean rootfs_debian_i386.ext3"
			rm -rf rootfs_debian_i386.ext3
		fi
		prepare_rootfs
		build_rootfs
		if [ ! -f "${KERNEL_IMAGE}" ]
		then
			echo "canot find kernel image in ${KERNEL_IMAGE}, pls run build_kernel command firstly!!"
			echo "./run_debian_i386.sh build_kernel"
			clean && exit 1
		fi
		echo "using ${KERNEL_IMAGE}"
		if [ ! -f "${ROOTFS_IMAGE}" ]
		then
			echo "canot find rootfs image ${ROOTFS_IMAGE}, pls run build_rootfs command firstly!!"
			echo "sudo ./run_debian_i386.sh build_rootfs"
			clean && exit 1
		fi
		echo "using ${ROOTFS_IMAGE}"
		run_qemu_debian
		;;
	*)
		usage
		;;
esac

clean
echo "Bye bye~"
