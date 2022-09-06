/* -*- linux-c -*- ------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *   Copyright 2009 Intel Corporation; author H. Peter Anvin
 *
 *   This file is part of the Linux kernel, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

/*
 * Main module for the real-mode kernel code
 */

#include "boot.h"

struct boot_params boot_params __attribute__((aligned(16)));

char *HEAP = _end;
char *heap_end = _end;		/* Default end of heap = no heap */

/*
 * Copy the header into the boot parameter block.  Since this
 * screws up the old-style command line protocol, adjust by
 * filling in the new-style command line pointer instead.
 */

static void copy_boot_params(void)
{
	struct old_cmdline {
		u16 cl_magic;
		u16 cl_offset;
	};
	const struct old_cmdline * const oldcmd =
		(const struct old_cmdline *)OLD_CL_ADDRESS;

	BUILD_BUG_ON(sizeof boot_params != 4096);
	memcpy(&boot_params.hdr, &hdr, sizeof hdr);

	if (!boot_params.hdr.cmd_line_ptr &&
	    oldcmd->cl_magic == OLD_CL_MAGIC) {
		/* Old-style command line protocol. */
		u16 cmdline_seg;

		/* Figure out if the command line falls in the region
		   of memory that an old kernel would have copied up
		   to 0x90000... */
		if (oldcmd->cl_offset < boot_params.hdr.setup_move_size)
			cmdline_seg = ds();
		else
			cmdline_seg = 0x9000;

		boot_params.hdr.cmd_line_ptr =
			(cmdline_seg << 4) + oldcmd->cl_offset;
	}
}

/*
 * Query the keyboard lock status as given by the BIOS, and
 * set the keyboard repeat rate to maximum.  Unclear why the latter
 * is done here; this might be possible to kill off as stale code.
 */
static void keyboard_init(void)
{
	struct biosregs ireg, oreg;
	initregs(&ireg);

	ireg.ah = 0x02;		/* Get keyboard status */
	intcall(0x16, &ireg, &oreg);
	boot_params.kbd_status = oreg.al;

	ireg.ax = 0x0305;	/* Set keyboard repeat rate */
	intcall(0x16, &ireg, NULL);
}

/*
 * Get Intel SpeedStep (IST) information.
 * speedstep技术是通过降低cpu运行主频来达到降低功耗的技术，是intel专为笔记本cpu开发的，
 * 它使得笔记本cpu高速发展，使笔记本的功能越来越接近台式机。
 * speedstep技术支持可以动态增强应用性能和电力利用率。
 */
static void query_ist(void)
{
	struct biosregs ireg, oreg;

	/* Some older BIOSes apparently crash on this call, so filter
	   it from machines too old to have SpeedStep at all. */
	if (cpu.level < 6)
		return;

	initregs(&ireg);
	ireg.ax  = 0xe980;	 /* IST Support */
	ireg.edx = 0x47534943;	 /* Request value */
	intcall(0x15, &ireg, &oreg);

	boot_params.ist_info.signature  = oreg.eax;
	boot_params.ist_info.command    = oreg.ebx;
	boot_params.ist_info.event      = oreg.ecx;
	boot_params.ist_info.perf_level = oreg.edx;
}

/*
 * Tell the BIOS what CPU mode we intend to run in.
 */
static void set_bios_mode(void)
{
#ifdef CONFIG_X86_64
	struct biosregs ireg;

	initregs(&ireg);
	ireg.ax = 0xec00;
	ireg.bx = 2;
	intcall(0x15, &ireg, NULL);
#endif
}

static void init_heap(void)
{
	char *stack_end;

	if (boot_params.hdr.loadflags & CAN_USE_HEAP) {
		asm("leal %P1(%%esp),%0"
		    : "=r" (stack_end) : "i" (-STACK_SIZE));

		heap_end = (char *)
			((size_t)boot_params.hdr.heap_end_ptr + 0x200);
		if (heap_end > stack_end)
			heap_end = stack_end;
	} else {
		/* Boot protocol 2.00 only, no heap available */
		puts("WARNING: Ancient bootloader, some functionality "
		     "may be limited!\n");
	}
}

// 这一段C代码还是系统处于实模式下所执行的代码
void main(void)
{
	/* First, copy the boot header into the "zeropage" */
	copy_boot_params();

	/* Initialize the early-boot console */
	// 更新 boot_params.hdr.cmd_line_ptr
	console_init();
	if (cmdline_find_option_bool("debug"))
		puts("early console in setup code\n");

	/* End of heap check */
	init_heap();

	/* Make sure we have all the proper CPU support */
	// 查看当前CPU level，如果低于系统预设的最低CPU level，则系统停止运行
	// 检查当前CPU与内核匹配
	if (validate_cpu()) {
		puts("Unable to boot - please use a kernel appropriate "
		     "for your CPU.\n");
		die();
	}

	/* Tell the BIOS what CPU mode we intend to run in. */
	// 实模式转为长模式，0xec00 开启地址线
	set_bios_mode();

	/* Detect memory layout */
	// 分别使用e820/e801/88方式探测内存
	// 循环探测，构建boot_params.e820_map数组
	// 每项包含：内存段起始地址 + 内存段大小 + 内存段类型
	detect_memory();

	/* Set keyboard repeat rate (why?) and query the lock flags */
	/*
	1. 通过中断获得键盘状态
	2. 设置键盘的按键检测频率
	*/
	keyboard_init();

	/* Query MCA information */
	// query_mca 方法调用0x15中断来获取机器的型号信息，BIOS版本以及其他一些硬件相关的属性
	// 初始化 boot_params.sys_desc_table 数据
	query_mca();

	/* Query Intel SpeedStep (IST) information */
	// ireg.ax  = 0xe980;	 /* IST Support */
	// intcall(0x15, &ireg, &oreg);
	// boot_params.ist_info.signature
	// boot_params.ist_info.command
	// boot_params.ist_info.event
	// boot_params.ist_info.perf_level
	query_ist();

	/* Query APM information */
	// 检查对高级电源管理（APM）BIOS的支持
	// boot_params.apm_bios_info.cseg
	// boot_params.apm_bios_info.offset
	// boot_params.apm_bios_info.cseg_16
	// boot_params.apm_bios_info.dseg
	// boot_params.apm_bios_info.cseg_len
	// boot_params.apm_bios_info.cseg_16_len
	// boot_params.apm_bios_info.dseg_len
	// boot_params.apm_bios_info.version
	// boot_params.apm_bios_info.flags
#if defined(CONFIG_APM) || defined(CONFIG_APM_MODULE)
	query_apm_bios();
#endif

	/* Query EDD information */
	// 如果BIOS支持增强磁盘驱动服务（Enhanced Disk drive service，EDD），
	// 它就调用相应的BIOS中断向量服务在RAM中建立系统可用的硬盘表
	// BIOS Enhanced Disk Device Services (EDD) 3.0 provides the ability for
	// disk adapter BIOSs to tell the OS what it believes is the boot disk.
	// 所用是直接告诉os，那块硬盘是可用的引导盘。os不用花额外时间和算力去探测
	// boot_params.eddbuf
	// boot_params.edd_mbr_sig_buffer
	// boot_params.edd_mbr_sig_buf_entries
#if defined(CONFIG_EDD) || defined(CONFIG_EDD_MODULE)
	    query_edd();
#endif

	/* Set the video mode */
	set_video();

	/* Do the last things and invoke protected mode */
	// 关键
	go_to_protected_mode();
}
