# Makefile for RISC-V toolchain; run 'make help' for usage. set XLEN here to 32 or 64.

XLEN     := 64
ROOT     := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RISCV    := $(PWD)/install$(XLEN)
DEST     := $(abspath $(RISCV))
PATH     := $(DEST)/bin:$(PATH)

TOOLCHAIN_PREFIX := $(ROOT)/buildroot/output/host/bin/riscv$(XLEN)-buildroot-linux-gnu-
CC          := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY     := $(TOOLCHAIN_PREFIX)objcopy
MKIMAGE     := u-boot/tools/mkimage

NR_CORES := $(shell nproc)

##################################################################
##																##
##			User Macros... Change it here or in the terminal    ##
##																##
##################################################################
IRQC					:= plic
GUEST					:=
LINUX_VER_DEF			:= linux-6.1-rc4-aia
PLATFORM_RAW 			:= alsaqr
OPENSBI_DIR				:= opensbi

# SBI options
PLATFORM := fpga/$(PLATFORM_RAW)
sbi-mk = PLATFORM=$(PLATFORM) CROSS_COMPILE=$(TOOLCHAIN_PREFIX)
ifeq ($(XLEN), 32)
sbi-mk += PLATFORM_RISCV_ISA=rv32ima PLATFORM_RISCV_XLEN=32
else
sbi-mk += PLATFORM_RISCV_ISA=rv64imafdc PLATFORM_RISCV_XLEN=64
endif

# U-Boot options
ifeq ($(XLEN), 32)
UIMAGE_LOAD_ADDRESS := 0x80400000
UIMAGE_ENTRY_POINT  := 0x80400000
else
UIMAGE_LOAD_ADDRESS := 0x80200000
UIMAGE_ENTRY_POINT  := 0x80200000
endif

# default configure flags
tests-co              = --prefix=$(RISCV)/target

# specific flags and rules for 32 / 64 version
ifeq ($(XLEN), 32)
isa-sim-co            = --prefix=$(RISCV) --with-isa=RV32IMA --with-priv=MSU
else
isa-sim-co            = --prefix=$(RISCV)
endif

BAO_CONFIG				:= $(PLATFORM_RAW)-$(GUEST)-$(IRQC)
#####################################################################
##																   ##
##		Dirty way of doing this :( But I really want to make       ## 
##      it easier for the end user of this Makefile                ##
##																   ##
#####################################################################
# if GUEST is defined (i.e., we will run bao rule) set the openSBI payload to bao
ifneq ($(GUEST),)
	LINUX_VER  := $(LINUX_VER_DEF)
	FW_PAYLOAD := $(RISCV)/bao.bin
else
# if LINUX_VER is defined (i.e., we will run linux rule) set openSBI payload to linux otherwise, use baremetal
ifneq ($(LINUX_VER),)
	FW_PAYLOAD := $(RISCV)/Image
else
	FW_PAYLOAD := $(RISCV)/baremetal.bin
endif
endif


ifeq ($(IRQC), plic)
IRQC_BAO				:= PLIC
else ifeq ($(IRQC), aplic)
IRQC_BAO				:= APLIC
else ifeq ($(IRQC), aia)
IRQC_BAO				:= AIA
endif

# default make flags
isa-sim-mk              = -j$(NR_CORES)
tests-mk         		= -j$(NR_CORES)
buildroot-mk       		= -j$(NR_CORES)
linux-mk       			= -j$(NR_CORES)

# linux image
buildroot_defconfig = configs/buildroot$(XLEN)_defconfig
linux_defconfig = configs/linux$(XLEN)_defconfig
busybox_defconfig = configs/busybox$(XLEN).config

install-dir:
	mkdir -p $(RISCV)

$(RISCV)/toolchain: $(buildroot_defconfig) $(busybox_defconfig) 
	make -C buildroot defconfig BR2_DEFCONFIG=../$(buildroot_defconfig)
	make -C buildroot host-gcc-final $(buildroot-mk)

$(RISCV)/rootfs.cpio: $(buildroot_defconfig) $(busybox_defconfig)
	mkdir -p $(RISCV)
	make -C buildroot $(buildroot-mk)
	cp $(ROOT)/buildroot/output/images/rootfs.cpio $@

$(RISCV)/vmlinux: $(RISCV)/rootfs.cpio
	cp $(linux_defconfig) $(ROOT)/local-linux/$(LINUX_VER)/arch/riscv/configs/defconfig
	make -C $(ROOT)/local-linux/$(LINUX_VER) ARCH=riscv CROSS_COMPILE=riscv64-buildroot-linux-gnu- $(linux-mk) defconfig
	make -C $(ROOT)/local-linux/$(LINUX_VER) ARCH=riscv CROSS_COMPILE=riscv64-buildroot-linux-gnu- $(linux-mk)
	cp $(ROOT)/local-linux/$(LINUX_VER)/vmlinux $@

$(RISCV)/Image: $(RISCV)/vmlinux
	$(OBJCOPY) -O binary -R .note -R .comment -S $< $@

$(RISCV)/baremetal.bin:
	make -C $(ROOT)/bao-baremetal-guest PLATFORM=$(PLATFORM_RAW)
	cp $(ROOT)/bao-baremetal-guest/build/$(PLATFORM_RAW)/baremetal.bin $@
	cp $(ROOT)/bao-baremetal-guest/build/$(PLATFORM_RAW)/baremetal.elf $(RISCV)/baremetal.elf

$(RISCV)/$(PLATFORM_RAW).dtb:
	dtc -I dts $(ROOT)/dtbs/$(PLATFORM_RAW)-$(IRQC).dts -O dtb -o $(ROOT)/dtbs/bins/$(PLATFORM_RAW)-$(IRQC).dtb 
	cp $(ROOT)/dtbs/bins/$(PLATFORM_RAW)-$(IRQC).dtb $@

$(RISCV)/$(PLATFORM_RAW)-minimal.dtb:
	dtc -I dts $(ROOT)/dtbs/$(PLATFORM_RAW)-linux-guest-$(IRQC).dts -O dtb -o $(ROOT)/dtbs/bins/$(PLATFORM_RAW)-linux-guest-$(IRQC).dtb 
	cp $(ROOT)/dtbs/bins/$(PLATFORM_RAW)-linux-guest-$(IRQC).dtb $@

$(RISCV)/linux_wrapper: $(RISCV)/Image $(RISCV)/alsaqr-minimal.dtb
	make -C linux-wrapper CROSS_COMPILE=riscv64-unknown-elf- ARCH=rv64 IMAGE=$< DTB=$(RISCV)/alsaqr-minimal.dtb TARGET=$@

$(RISCV)/bao.bin:
	make -C bao-hypervisor CONFIG=$(BAO_CONFIG) PLATFORM=$(PLATFORM_RAW) CROSS_COMPILE=riscv64-unknown-elf- IRQC=$(IRQC_BAO)
	cp bao-hypervisor/bin/$(PLATFORM_RAW)/$(BAO_CONFIG)/bao.elf $(RISCV)/bao.elf
	cp bao-hypervisor/bin/$(PLATFORM_RAW)/$(BAO_CONFIG)/bao.bin $(RISCV)/bao.bin

$(RISCV)/fw_payload.bin: $(RISCV)/$(PLATFORM_RAW).dtb
	make -C $(OPENSBI_DIR) FW_PAYLOAD_PATH=$(FW_PAYLOAD) $(sbi-mk) FW_FDT_PATH=$(RISCV)/$(PLATFORM_RAW).dtb TARGET_FREQ=40000000 NUM_HARTS=2
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

$(RISCV)/baremetal_qemu.bin:
	make -C $(ROOT)/bao-baremetal-guest PLATFORM=qemu-riscv64-virt
	cp $(ROOT)/bao-baremetal-guest/build/qemu-riscv64-virt/baremetal.bin $(RISCV)/baremetal.bin
	cp $(ROOT)/bao-baremetal-guest/build/qemu-riscv64-virt/baremetal.elf $(RISCV)/baremetal.elf

$(RISCV)/fw_payload_qemu.bin:
	make -C $(OPENSBI_DIR) FW_PAYLOAD_PATH=$(FW_PAYLOAD) CROSS_COMPILE=$(TOOLCHAIN_PREFIX) PLATFORM=generic
	cp $(OPENSBI_DIR)/build/platform/generic/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp $(OPENSBI_DIR)/build/platform/generic/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

RUN_PLIC:
	qemu-system-riscv64 -nographic -M virt -cpu rv64 -m 4G -smp 4 -serial pty -bios $(RISCV)/fw_payload.elf -device virtio-serial-device -chardev pty,id=serial3 -device virtconsole,chardev=serial3 -S -gdb tcp:localhost:9000

RUN_APLIC:
	qemu-system-riscv64 -nographic -M virt -machine aia=aplic -cpu rv64 -m 4G -smp 4 -serial pty -bios $(RISCV)/fw_payload.elf -device virtio-serial-device -chardev pty,id=serial3 -device virtconsole,chardev=serial3 -S -gdb tcp:localhost:9000
#-machine dumpdtb=qemu.dtb
RUN_IMSIC:
	qemu-system-riscv64 -nographic -M virt -machine aia=aplic-imsic,aia_guests=$(AIA_GUESTS) -cpu rv64 -m 4G -smp $(N_HARTS) -serial pty -bios $(RISCV)/fw_payload.elf -device virtio-serial-device -chardev pty,id=serial3 -device virtconsole,chardev=serial3 -S -gdb tcp:localhost:9000


# specific recipes
gcc: $(CC)
toolchain: $(RISCV)/toolchain
rootfs: $(RISCV)/toolchain $(RISCV)/rootfs.cpio
vmlinux: $(RISCV)/vmlinux
dtb: $(RISCV)/$(PLATFORM_RAW).dtb
linux: $(RISCV)/Image $(RISCV)/fw_payload.bin
baremetal: $(RISCV)/baremetal.bin $(RISCV)/fw_payload.bin
baremetal-qemu: $(RISCV)/baremetal_qemu.bin $(RISCV)/fw_payload_qemu.bin
linux-qemu: $(RISCV)/Image $(RISCV)/fw_payload_qemu.bin
bao:
ifeq ($(GUEST),baremetal)
	@$(MAKE) -f $(MAKEFILE_LIST) $(RISCV)/baremetal.bin $(RISCV)/$(PLATFORM_RAW).dtb $(RISCV)/bao.bin $(RISCV)/fw_payload.bin
else ifeq ($(GUEST),linux)
	@$(MAKE) -f $(MAKEFILE_LIST) $(RISCV)/$(PLATFORM_RAW).dtb $(RISCV)/linux_wrapper $(RISCV)/bao.bin $(RISCV)/fw_payload.bin
else
	 $(error GUEST variable is not set to valid value)
endif
run-plic:RUN_PLIC
run-aplic:RUN_APLIC
run-imsic:RUN_IMSIC

clean:
	rm -rf $(RISCV)/fw_payload.bin
	rm -rf $(RISCV)/fw_payload.elf
	rm -rf $(RISCV)/alsaqr.dtb
	rm -rf $(RISCV)/alsaqr-minimal.dtb
	rm -rf $(RISCV)/linux_wrapper.bin
	rm -rf $(RISCV)/linux_wrapper.elf
	rm -rf $(RISCV)/bao.bin
	rm -rf $(RISCV)/bao.elf
	rm -rf $(RISCV)/baremetal.bin
	rm -rf $(RISCV)/baremetal.elf
	make -C $(OPENSBI_DIR) clean
	make -C bao-hypervisor clean
	make -C bao-baremetal-guest clean

clean-baremetal:
	rm -rf $(RISCV)/baremetal.bin
	rm -rf $(RISCV)/baremetal.elf
	make -C $(ROOT)/bao-baremetal-guest clean

clean-linux:
	rm -rf $(RISCV)/Image
	make -C $(ROOT)/local-linux/$(LINUX_VER) clean

clean-all: clean
	rm -rf $(ROOT)/dtbs/bins/*
	rm -rf $(RISCV)/rootfs.cpio
	rm -rf $(RISCV)/vmlinux
	rm -rf $(RISCV)/Image

clean-buildroot: clean-all
	make -C buildroot clean

.PHONY: gcc vmlinux images help fw_payload.bin uImage alsaqr.dtb

help:
	@echo "usage: $(MAKE) [tool/img] ..."
	@echo ""
	@echo "install compiler with"
	@echo "    make gcc or make toolchain"
	@echo ""
	@echo "build root file system for linux"
	@echo "    make rootfs"
	@echo ""
	@echo "build linux images for [alsaqr/ariane]"
	@echo "    make linux LINUX_VER=<linux-version> {options}"
	@echo "       where options can be:"
	@echo "       PLATFORM_RAW=[alsaqr(default)/ariane]"
	@echo "       IRQC=[plic(default)/aplic/aia]"
	@echo ""
	@echo "build baremetal images for [alsaqr/ariane]"
	@echo "    make baremetal {options}"
	@echo "       where options can be:"
	@echo "       PLATFORM_RAW=[alsaqr(default)/ariane]"
	@echo "       IRQC=[plic(default)/aplic/aia]"
	@echo "    WARNING 0: We must also define the IRQC in baremetal source code..."
	@echo "               arch/riscv/inc/irq.h"
	@echo "               We will update it in a near future to do everything from here"
	@echo ""
	@echo "build bao images for [alsaqr/ariane]"
	@echo "    make bao GUEST=[baremetal/linux] {options}"
	@echo "       where options can be:"
	@echo "       PLATFORM_RAW=[alsaqr(default)/ariane]"
	@echo "       IRQC=[plic(default)/aplic/aia]"
	@echo "    WARNING 1: The config file in bao folder should follow the rule:"
	@echo "               <platform>-<guest>-<irqc>"
	@echo "               We will update it in a near future to do everything from here"
	@echo "    WANING 2: If the guest is a baremetal see WARING 0"
	@echo ""
	@echo "There are two clean targets:"
	@echo "    Clean only build object but not the Linux image (not really necessary once it is built...)"
	@echo "        make clean"
	@echo "    Clean everything (including Linux)"
	@echo "        make clean-all"
	@echo "    Clean REALLY everything (including toolchain etc)"
	@echo "        make clean-buildroot"
	@echo ""
	@echo "==========================================================="
	@echo "==                    EXAMPLES                           =="
	@echo "==========================================================="
	@echo "==    make baremmetal                                    =="
	@echo "==    make linux LINUX_VER=linux-6.1-rc4-aia IRQC=aia    =="
	@echo "==    make linux LINUX_VER=linux-6.1-rc4-aia IRQC=plic   =="
	@echo "==    make bao GUEST=baremetal                           =="
	@echo "==    make bao GUEST=linux IRQC=aplic                    =="
	@echo "==========================================================="
