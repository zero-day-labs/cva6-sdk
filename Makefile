
##################################################################
##																##
##			Plat Macros... Change it here or in the terminal    ##
##																##
##################################################################
XLEN     := 64
PLATFORM_RAW := alsaqr
PLAT_TARGET_FREQ := 40000000 
PLAT_NUM_HARTS := 2
##################################################################


NR_CORES := $(shell nproc)
ROOT     := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RISCV    := $(ROOT)/install$(XLEN)
DEST     := $(abspath $(RISCV))
PATH     := $(DEST)/bin:$(PATH)

# Paths to folders
BENCHMARK_DIR := $(ROOT)/benchmarks
SPLASH3_DIR := $(BENCHMARK_DIR)/Splash-3
CACHETEST_DIR := $(BENCHMARK_DIR)/cachetest

TOOLS_DIR := $(ROOT)/tools
BUILDROOT_DIR := $(TOOLS_DIR)/buildroot
LINUX_WRAPPER_DIR := $(TOOLS_DIR)/linux-wrapper

SWSTACK_DIR := $(ROOT)/stack
OPENSBI_DIR := $(SWSTACK_DIR)/opensbi
LINUX_DIR := $(SWSTACK_DIR)/linux
ROOTFS_DIR := $(LINUX_DIR)/rootfs
BAREMETAL_DIR := $(SWSTACK_DIR)/baremetal-app
BAO_DIR := $(SWSTACK_DIR)/bao-hypervisor
DTB_DIR := $(SWSTACK_DIR)/dtbs

CONFIGS_DIR := $(ROOT)/configs

TOOLCHAIN_UNK := riscv64-unknown-elf-
TOOLCHAIN_PREFIX := $(BUILDROOT_DIR)/output/host/bin/riscv$(XLEN)-buildroot-linux-gnu-
CC          := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY     := $(TOOLCHAIN_PREFIX)objcopy

# Qemu defaults
QEMU_N_HARTS := 4

# SBI options
FW_FDT_PATH := $(RISCV)/$(PLATFORM_RAW).dtb
PLATFORM := fpga/$(PLATFORM_RAW)

# If we are compiling the baremetal app set the payload to it
ifneq ($(BARE),)
	FW_PAYLOAD := $(RISCV)/baremetal.bin
endif

# if BAO-GUEST is defined (i.e., we will run bao rule) set the openSBI payload to bao
ifneq ($(BAO-GUEST),)
# Check if BAO-GUEST is either "linux" or "baremetal"
    ifneq ($(filter $(BAO-GUEST),linux baremetal),)
		BAO_CONFIG := $(PLATFORM_RAW)-$(BAO-GUEST)-plic
		FW_PAYLOAD := $(RISCV)/bao.bin
    else
        $(error BAO-GUEST must be either "linux" or "baremetal")
    endif
endif

# If QEMU is defined, change the target platform
ifneq ($(QEMU),)
	PLATFORM_RAW := qemu-riscv64-virt
	PLATFORM := generic
	ifneq ($(BAO-GUEST),)
		BAO_CONFIG := qemu-$(BAO-GUEST)-plic
	endif
else
	TARGET_FREQ := $(PLAT_TARGET_FREQ) 
	NUM_HARTS := $(PLAT_NUM_HARTS)
endif

sbi-mk = PLATFORM=$(PLATFORM) FW_PAYLOAD_PATH=$(FW_PAYLOAD) CROSS_COMPILE=$(TOOLCHAIN_PREFIX) $(if $(FW_FDT_PATH),FW_FDT_PATH=$(FW_FDT_PATH),) $(if $(TARGET_FREQ),TARGET_FREQ=$(TARGET_FREQ),) $(if $(NUM_HARTS),NUM_HARTS=$(NUM_HARTS),) 
ifeq ($(XLEN), 32)
sbi-mk += PLATFORM_RISCV_ISA=rv32ima PLATFORM_RISCV_XLEN=32
else
sbi-mk += PLATFORM_RISCV_ISA=rv64imafdc PLATFORM_RISCV_XLEN=64
endif

# default make flags
buildroot-mk       		= -j$(NR_CORES)

# linux image
buildroot_defconfig = $(CONFIGS_DIR)/buildroot$(XLEN)_defconfig
linux_defconfig = $(CONFIGS_DIR)/linux$(XLEN)_defconfig
busybox_defconfig = $(CONFIGS_DIR)/busybox$(XLEN).config

install-dir:
	mkdir -p $(RISCV)

build-buildroot-defconfig:
	rm -rf $(buildroot_defconfig) 
	cp $(buildroot_defconfig)_base $(buildroot_defconfig)
	@echo "BR2_ROOTFS_OVERLAY=\"$(ROOTFS_DIR)\"" >> $(buildroot_defconfig) 
	@echo "BR2_PACKAGE_BUSYBOX_CONFIG=\"$(busybox_defconfig)\"" >> $(buildroot_defconfig) 
	@echo "BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=\"$(linux_defconfig)\"" >> $(buildroot_defconfig) 

$(CC): build-buildroot-defconfig $(linux_defconfig) $(busybox_defconfig)
	make -C $(BUILDROOT_DIR) defconfig BR2_DEFCONFIG=$(buildroot_defconfig)
	make -C $(BUILDROOT_DIR) host-gcc-final $(buildroot-mk)

all: $(CC)

# benchmark for the cache subsystem
$(ROOTFS_DIR)/cachetest.elf: $(CC)
	cd $(CACHETEST_DIR)/ && $(CC) cachetest.c -o cachetest.elf
	cp $(CACHETEST_DIR)/cachetest.elf $@

$(ROOTFS_DIR)/perf: $(CC)
	make -C $(SPLASH3_DIR)/codes all
	mkdir -p $@
	cp -r $(SPLASH3_DIR)/codes/splash3 $@/splash3
	cp -r $(SPLASH3_DIR)/codes/kernels $@/splash3/codes

$(RISCV)/vmlinux: build-buildroot-defconfig $(CC) $(ROOTFS_DIR)/cachetest.elf $(ROOTFS_DIR)/perf
	mkdir -p $(RISCV)
	make -C $(BUILDROOT_DIR) $(buildroot-mk)
	cp $(BUILDROOT_DIR)/output/images/vmlinux $@

$(RISCV)/Image: $(RISCV)/vmlinux
	$(OBJCOPY) -O binary -R .note -R .comment -S $< $@

$(RISCV)/Image.gz: $(RISCV)/Image
	gzip -9 -k --force $< > $@

$(RISCV)/baremetal.bin:
	make -C $(BAREMETAL_DIR) PLATFORM=$(PLATFORM_RAW) CROSS_COMPILE=$(TOOLCHAIN_UNK)
	mkdir -p $(RISCV)
	cp $(BAREMETAL_DIR)/build/$(PLATFORM_RAW)/baremetal.bin $@
	cp $(BAREMETAL_DIR)/build/$(PLATFORM_RAW)/baremetal.elf $(RISCV)/baremetal.elf

$(RISCV)/$(PLATFORM_RAW).dtb:
	dtc -I dts $(DTB_DIR)/$(PLATFORM_RAW)-plic.dts -O dtb -o $(DTB_DIR)/bins/$(PLATFORM_RAW)-plic.dtb 
	cp $(DTB_DIR)/bins/$(PLATFORM_RAW)-plic.dtb $@

$(RISCV)/$(PLATFORM_RAW)-minimal.dtb:
	dtc -I dts $(DTB_DIR)/$(PLATFORM_RAW)-linux-guest-plic.dts -O dtb -o $(DTB_DIR)/bins/$(PLATFORM_RAW)-linux-guest-plic.dtb
	cp $(DTB_DIR)/bins/$(PLATFORM_RAW)-linux-guest-plic.dtb $@

$(RISCV)/linux_wrapper: $(RISCV)/Image $(RISCV)/$(PLATFORM_RAW)-minimal.dtb
	make -C $(LINUX_WRAPPER_DIR) CROSS_COMPILE=$(TOOLCHAIN_UNK) ARCH=rv64 IMAGE=$< DTB=$(RISCV)/$(PLATFORM_RAW)-minimal.dtb TARGET=$@

$(RISCV)/bao.bin:
	make -C $(BAO_DIR) CONFIG=$(BAO_CONFIG) PLATFORM=$(PLATFORM_RAW) CROSS_COMPILE=$(TOOLCHAIN_UNK) CPPFLAGS=-DGUEST_IMGS=$(RISCV)
	cp $(BAO_DIR)/bin/$(PLATFORM_RAW)/$(BAO_CONFIG)/bao.elf $(RISCV)/bao.elf
	cp $(BAO_DIR)/bin/$(PLATFORM_RAW)/$(BAO_CONFIG)/bao.bin $(RISCV)/bao.bin

$(RISCV)/fw_payload.bin: $(RISCV)/$(PLATFORM_RAW).dtb
	make -C $(OPENSBI_DIR) $(sbi-mk)
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

$(RISCV)/test_fw_payload.bin:
	make -C $(OPENSBI_DIR) $(sbi-mk)
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp $(OPENSBI_DIR)/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

# need to run flash-sdcard with sudo -E, be careful to set the correct SDDEVICE
# Number of sector required for FWPAYLOAD partition (each sector is 512B)
FWPAYLOAD_SECTORSTART := 2048
FWPAYLOAD_SECTORSIZE = $(shell ls -l --block-size=512 $(RISCV)/fw_payload.bin | cut -d " " -f5 )
FWPAYLOAD_SECTOREND = $(shell echo $(FWPAYLOAD_SECTORSTART)+$(FWPAYLOAD_SECTORSIZE) | bc)
SDDEVICE_PART1 = $(shell lsblk $(SDDEVICE) -no PATH | head -2 | tail -1)
SDDEVICE_PART2 = $(shell lsblk $(SDDEVICE) -no PATH | head -3 | tail -1)
# Always flash uImage at 512M, easier for u-boot boot command
UIMAGE_SECTORSTART := 512M
flash-sdcard: format-sd
	dd if=$(RISCV)/fw_payload.bin of=$(SDDEVICE_PART1) status=progress oflag=sync bs=1M
	dd if=$(RISCV)/uImage         of=$(SDDEVICE_PART2) status=progress oflag=sync bs=1M

format-sd: $(SDDEVICE)
	@test -n "$(SDDEVICE)" || (echo 'SDDEVICE must be set, Ex: make flash-sdcard SDDEVICE=/dev/sdc' && exit 1)
	sgdisk --clear -g --new=1:$(FWPAYLOAD_SECTORSTART):$(FWPAYLOAD_SECTOREND) --new=2:$(UIMAGE_SECTORSTART):0 --typecode=1:3000 --typecode=2:8300 $(SDDEVICE)

# specific recipes
gcc: $(CC)

fw_payload.bin: $(RISCV)/fw_payload.bin
test_fw_payload.bin: $(RISCV)/test_fw_payload.bin

vmlinux: $(RISCV)/vmlinux
linux: $(RISCV)/Image $(RISCV)/fw_payload.bin
baremetal: $(RISCV)/baremetal.bin $(RISCV)/fw_payload.bin
bao:
ifeq ($(BAO-GUEST),baremetal)
	@$(MAKE) -f $(MAKEFILE_LIST) $(RISCV)/baremetal.bin $(RISCV)/bao.bin $(RISCV)/$(PLATFORM_RAW).dtb $(RISCV)/fw_payload.bin
else ifeq ($(BAO-GUEST),linux)
	@$(MAKE) -f $(MAKEFILE_LIST) $(RISCV)/$(PLATFORM_RAW).dtb $(RISCV)/linux_wrapper $(RISCV)/bao.bin $(RISCV)/fw_payload.bin
else
	 $(error BAO-GUEST must be either "linux" or "baremetal")
endif

images: $(CC) $(RISCV)/fw_payload.bin

alsaqr.dtb:
	make -C $(OPENSBI_DIR) $(sbi-mk) alsaqr.dts
	dtc -I dts $(OPENSBI_DIR)/platform/$(PLATFORM)/fdt_gen/alsaqr.dts -O dtb -o $@

# Qemu-related rules
bare-qemu:
	qemu-system-riscv64 -nographic -M virt -cpu rv64 -m 4G -smp $(QEMU_N_HARTS) -serial pty -bios $(RISCV)/fw_payload.elf -device virtio-serial-device -chardev pty,id=serial3 -device virtconsole,chardev=serial3 -S -gdb tcp:localhost:9000

lqemu:
	qemu-system-riscv64 -M virt -m 256M -nographic     -bios $(OPENSBI_DIR)/build/platform/generic/firmware/fw_jump.bin       -kernel install64/Image         -append "root=/dev/vda rw console=ttyS0"

# Clean-related rules
clean:
	rm -rf $(RISCV)/baremetal.*
	rm -rf $(RISCV)/bao.*
	rm -rf $(RISCV)/linux_wrapper.*
	rm -rf $(RISCV)/*.dtb
	rm -rf $(CACHETEST_DIR)/*.elf $(ROOTFS_DIR)/cachetest.elf
	make -C $(SPLASH3_DIR)/codes clean
	rm -rf $(ROOTFS_DIR)/perf/*
	rm -rf $(buildroot_defconfig)
	rm -rf $(RISCV)/fw_payload.bin $(RISCV)/Image.gz
	make -C $(OPENSBI_DIR) distclean
	make -C $(BAREMETAL_DIR) clean
	make -C $(BAO_DIR) clean

clean-all: clean
	rm -rf $(RISCV)
	make -C $(BUILDROOT_DIR) clean

.PHONY: gcc vmlinux images help fw_payload.bin alsaqr.dtb test_fw_payload.bin

help:
	@echo "usage: $(MAKE) [tool/img] ..."
	@echo ""
	@echo "install compiler with"
	@echo "    make gcc"
	@echo ""
	@echo "install [tool] with compiler"
	@echo "    where tool can be any one of:"
	@echo "        gcc"
	@echo ""
	@echo "build linux images for cva6"
	@echo "        make images"
	@echo "    for specific artefact"
	@echo "        make [vmlinux|fw_payload.bin]"
	@echo ""
	@echo "There are two clean targets:"
	@echo "    Clean only build object"
	@echo "        make clean"
	@echo "    Clean everything (including toolchain etc)"
	@echo "        make clean-all"
