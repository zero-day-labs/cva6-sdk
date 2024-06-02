
##################################################################
##																##
##			Plat Macros... Change it here or in the terminal    ##
##																##
##################################################################
XLEN     := 64
PLAT := alsaqr
PLAT_TARGET_FREQ := 40000000 
PLAT_NUM_HARTS := 2
PLAT_IRQC := plic
##################################################################


PLATFORM_RAW := $(PLAT)

# Qemu defaults
QEMU_N_HARTS := $(PLAT_NUM_HARTS)

ifeq ($(PLAT_IRQC), plic)
IRQC_BAO				:= PLIC
QEMU_IRQC :=
else ifeq ($(PLAT_IRQC), aplic)
IRQC_BAO				:= APLIC
QEMU_IRQC := -machine aia=aplic
else ifeq ($(PLAT_IRQC), aia)
IRQC_BAO				:= AIA
QEMU_IRQC := -machine aia=aplic-imsic,aia_guests=1
endif

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
LINUX_VER := linux-6.1-rc4-aia
ROOTFS_DIR := $(LINUX_DIR)/rootfs
BAREMETAL_DIR := $(SWSTACK_DIR)/baremetal-app
BAO_DIR := $(SWSTACK_DIR)/bao-hypervisor
DTB_DIR := $(SWSTACK_DIR)/dtbs

CONFIGS_DIR := $(ROOT)/configs

TOOLCHAIN_UNK := riscv64-unknown-elf-
TOOLCHAIN_PREFIX := $(BUILDROOT_DIR)/output/host/bin/riscv$(XLEN)-buildroot-linux-gnu-
CC          := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY     := $(TOOLCHAIN_PREFIX)objcopy

# SBI options
FW_FDT_PATH := $(RISCV)/$(PLATFORM_RAW).dtb
PLATFORM := fpga/$(PLATFORM_RAW)
FW_PAYLOAD := $(RISCV)/Image

# If we are compiling the baremetal app set the payload to it
ifneq ($(BARE),)
	FW_PAYLOAD := $(RISCV)/baremetal.bin
endif

# if BAO-GUEST is defined (i.e., we will run bao rule) set the openSBI payload to bao
ifneq ($(BAO-GUEST),)
# Check if BAO-GUEST is either "linux" or "baremetal"
    ifneq ($(filter $(BAO-GUEST),linux baremetal),)
		BAO_CONFIG := $(PLATFORM_RAW)-$(BAO-GUEST)-$(PLAT_IRQC)
		FW_PAYLOAD := $(RISCV)/bao.bin
    else
        $(error BAO-GUEST must be either "linux" or "baremetal")
    endif
endif

# If QEMU is defined, change the target platform
ifeq ($(PLAT),qemu)
	PLATFORM_RAW := qemu-riscv64-virt
	PLATFORM := generic
	FW_FDT_PATH :=	
	ifneq ($(BAO-GUEST),)
		BAO_CONFIG := qemu-$(BAO-GUEST)-$(PLAT_IRQC)
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
buildroot-mk = -j$(NR_CORES)
linux-mk     = -j$(NR_CORES)

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

build-linux-defconfig:
	rm -rf $(linux_defconfig) 
	cp $(linux_defconfig)_base $(linux_defconfig)
	@echo "CONFIG_INITRAMFS_SOURCE=\"$(RISCV)/rootfs.cpio\"" >> $(linux_defconfig) 

$(CC): build-buildroot-defconfig build-linux-defconfig $(busybox_defconfig)
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

$(RISCV)/rootfs.cpio: build-buildroot-defconfig $(busybox_defconfig) $(CC) $(ROOTFS_DIR)/cachetest.elf $(ROOTFS_DIR)/perf
	mkdir -p $(RISCV)
	make -C $(BUILDROOT_DIR) $(buildroot-mk)
	cp $(BUILDROOT_DIR)/output/images/rootfs.cpio $@

$(RISCV)/vmlinux: build-linux-defconfig $(RISCV)/rootfs.cpio
	cp $(linux_defconfig) $(LINUX_DIR)/$(LINUX_VER)/arch/riscv/configs/defconfig
	make -C $(LINUX_DIR)/$(LINUX_VER) ARCH=riscv CROSS_COMPILE=$(TOOLCHAIN_PREFIX) $(linux-mk) defconfig
	make -C $(LINUX_DIR)/$(LINUX_VER) ARCH=riscv CROSS_COMPILE=$(TOOLCHAIN_PREFIX) $(linux-mk)
	cp $(LINUX_DIR)/$(LINUX_VER)/vmlinux $@

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
	make -C $(DTB_DIR) dts PLAT=$(PLATFORM_RAW) TARGET_FREQ=$(PLAT_TARGET_FREQ) NUM_HARTS=$(PLAT_NUM_HARTS) MINIMAL=n IRQC=$(PLAT_IRQC)
	dtc -I dts $(DTB_DIR)/$(PLATFORM_RAW).dts -O dtb -o $(DTB_DIR)/bins/$(PLATFORM_RAW).dtb 
	cp $(DTB_DIR)/bins/$(PLATFORM_RAW).dtb $@

$(RISCV)/$(PLATFORM_RAW)-minimal.dtb:
	make -C $(DTB_DIR) dts PLAT=$(PLATFORM_RAW)-minimal TARGET_FREQ=$(PLAT_TARGET_FREQ) NUM_HARTS=$(PLAT_NUM_HARTS) MINIMAL=y IRQC=$(PLAT_IRQC)
	dtc -I dts $(DTB_DIR)/$(PLATFORM_RAW)-minimal.dts -O dtb -o $(DTB_DIR)/bins/$(PLATFORM_RAW)-minimal.dtb
	cp $(DTB_DIR)/bins/$(PLATFORM_RAW)-minimal.dtb $@

$(RISCV)/linux_wrapper: $(RISCV)/Image $(RISCV)/$(PLATFORM_RAW)-minimal.dtb
	make -C $(LINUX_WRAPPER_DIR) CROSS_COMPILE=$(TOOLCHAIN_UNK) ARCH=rv64 IMAGE=$< DTB=$(RISCV)/$(PLATFORM_RAW)-minimal.dtb TARGET=$@

$(RISCV)/bao.bin:
	make -C $(BAO_DIR) CONFIG=$(BAO_CONFIG) PLATFORM=$(PLATFORM_RAW) CROSS_COMPILE=$(TOOLCHAIN_UNK) IRQC=$(IRQC_BAO) CPPFLAGS=-DGUEST_IMGS=$(RISCV)
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

# specific recipes
gcc: $(CC)

fw_payload.bin: $(RISCV)/fw_payload.bin
test_fw_payload.bin: $(RISCV)/test_fw_payload.bin

vmlinux: $(RISCV)/vmlinux
linux: $(RISCV)/Image $(RISCV)/fw_payload.bin
baremetal: $(RISCV)/baremetal.bin $(RISCV)/fw_payload.bin
bao:
ifeq ($(BAO-GUEST),baremetal)
	@$(MAKE) -f $(MAKEFILE_LIST) $(RISCV)/baremetal.bin $(RISCV)/bao.bin $(RISCV)/fw_payload.bin
else ifeq ($(BAO-GUEST),linux)
	@$(MAKE) -f $(MAKEFILE_LIST) $(RISCV)/linux_wrapper $(RISCV)/bao.bin $(RISCV)/fw_payload.bin
else
	 $(error BAO-GUEST must be either "linux" or "baremetal")
endif

images: $(CC) $(RISCV)/fw_payload.bin

# Qemu-related rules
qemu:
	qemu-system-riscv64 -nographic -M virt $(QEMU_IRQC) -cpu rv64 -m 4G -smp $(QEMU_N_HARTS) -serial pty -bios $(RISCV)/fw_payload.elf -device virtio-serial-device -chardev pty,id=serial3 -device virtconsole,chardev=serial3 -S -gdb tcp:localhost:9000

lqemu:
	qemu-system-riscv64 -M virt -m 256M -nographic     -bios $(OPENSBI_DIR)/build/platform/generic/firmware/fw_jump.bin       -kernel install64/Image         -append "root=/dev/vda rw console=ttyS0"

# Clean-related rules
clean:
	rm -rf $(RISCV)/vmlinux
	rm -rf $(RISCV)/rootfs.cpio
	rm -rf $(RISCV)/baremetal.*
	rm -rf $(RISCV)/bao.*
	rm -rf $(RISCV)/*.dtb
	rm -rf $(RISCV)/linux_wrapper.*
	rm -rf $(RISCV)/*.dtb
	rm -rf $(CACHETEST_DIR)/*.elf $(ROOTFS_DIR)/cachetest.elf
	make -C $(SPLASH3_DIR)/codes clean
	rm -rf $(ROOTFS_DIR)/perf/*
	rm -rf $(buildroot_defconfig)
	rm -rf $(RISCV)/fw_payload.* $(RISCV)/Image.gz
	make -C $(OPENSBI_DIR) distclean
	make -C $(BAREMETAL_DIR) clean
	make -C $(BAO_DIR) clean
	make -C $(DTB_DIR) clean NAME=$(PLATFORM_RAW) TARGET_FREQ=$(PLAT_TARGET_FREQ) NUM_HARTS=$(PLAT_NUM_HARTS)

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
