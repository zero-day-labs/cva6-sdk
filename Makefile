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

# SBI options
PLATFORM_RAW := alsaqr
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

IRQC					:= plic
BAO_CONFIG				:= alsaqr-linux-$(IRQC)
LINUX_VER				:= linux-6.1-rc4-aia

ifeq ($(IRQC), plic)
IRQC_BAO				:= PLIC
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

isa-sim: install-dir $(CC) 
	mkdir -p riscv-isa-sim/build
	cd riscv-isa-sim/build;\
	../configure $(isa-sim-co);\
	make $(isa-sim-mk);\
	make install;\
	cd $(ROOT)

tests: install-dir $(CC)
	mkdir -p riscv-tests/build
	cd riscv-tests/build;\
	autoconf;\
	../configure $(tests-co);\
	make $(tests-mk);\
	make install;\
	cd $(ROOT)

$(CC): $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig)
	make -C buildroot defconfig BR2_DEFCONFIG=../$(buildroot_defconfig)
	make -C buildroot host-gcc-final $(buildroot-mk)

all: $(CC) isa-sim

# $(RISCV)/vmlinux: $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig) $(CC)
# 	mkdir -p $(RISCV)
# 	make -C buildroot $(buildroot-mk)
# 	cp buildroot/output/images/vmlinux $@

$(RISCV)/toolchain: $(buildroot_defconfig) $(busybox_defconfig) 
	make -C buildroot defconfig BR2_DEFCONFIG=../$(buildroot_defconfig)
	make -C buildroot host-gcc-final $(buildroot-mk)

$(RISCV)/rootfs.cpio: $(buildroot_defconfig) $(busybox_defconfig) $(RISCV)/toolchain
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

$(RISCV)/alsaqr.dtb:
	dtc -I dts $(ROOT)/dtbs/alsaqr-$(IRQC).dts -O dtb -o $(ROOT)/dtbs/bins/alsaqr-$(IRQC).dtb 
	cp $(ROOT)/dtbs/bins/alsaqr-$(IRQC).dtb $@

$(RISCV)/alsaqr-minimal.dtb:
	dtc -I dts $(ROOT)/dtbs/alsaqr-linux-guest-$(IRQC).dts -O dtb -o $(ROOT)/dtbs/bins/alsaqr-linux-guest-$(IRQC).dtb 
	cp $(ROOT)/dtbs/bins/alsaqr-linux-guest-$(IRQC).dtb $@

$(RISCV)/fw_payload.bin: $(RISCV)/Image $(RISCV)/alsaqr.dtb
	make -C opensbi FW_PAYLOAD_PATH=$(RISCV)/Image $(sbi-mk) FW_FDT_PATH=$(RISCV)/alsaqr.dtb
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

$(RISCV)/linux_wrapper: $(RISCV)/Image $(RISCV)/alsaqr-minimal.dtb
	make -C linux-wrapper CROSS_COMPILE=riscv64-unknown-elf- ARCH=rv64 IMAGE=$< DTB=$(RISCV)/alsaqr-minimal.dtb TARGET=$@

$(RISCV)/bao.bin: $(RISCV)/linux_wrapper
	make -C bao-hypervisor CONFIG=$(BAO_CONFIG) PLATFORM=$(PLATFORM_RAW) CROSS_COMPILE=riscv64-unknown-elf- IRQC=$(IRQC_BAO)
	cp bao-hypervisor/bin/$(PLATFORM_RAW)/$(BAO_CONFIG)/bao.elf $(RISCV)/bao.elf
	cp bao-hypervisor/bin/$(PLATFORM_RAW)/$(BAO_CONFIG)/bao.bin $(RISCV)/bao.bin

$(RISCV)/bao_fw_payload.bin: $(RISCV)/bao.bin $(RISCV)/alsaqr.dtb
	make -C opensbi FW_PAYLOAD_PATH=$(RISCV)/bao.bin $(sbi-mk) FW_FDT_PATH=$(RISCV)/alsaqr.dtb
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

# specific recipes
gcc: $(CC)
toolchain: $(RISCV)/toolchain
rootfs: $(RISCV)/rootfs.cpio
vmlinux: $(RISCV)/vmlinux
dtb: $(RISCV)/alsaqr.dtb
local-linux-opensbi: $(RISCV)/fw_payload.bin
bao-linux: $(RISCV)/bao_fw_payload.bin

clean:
	rm -rf $(RISCV)/vmlinux
	rm -rf $(RISCV)/fw_payload.bin
	rm -rf $(RISCV)/fw_payload.elf
	rm -rf $(RISCV)/alsaqr.dtb
	rm -rf $(RISCV)/alsaqr-minimal.dtb
	rm -rf $(RISCV)/linux_wrapper
	rm -rf $(RISCV)/bao.bin
	make -C opensbi clean
	make -C bao-hypervisor clean

clean-linux:
	rm -rf $(RISCV)/Image
	make -C $(ROOT)/local-linux/$(LINUX_VER) clean

clean-buildroot:
	make -C buildroot clean

clean-all: clean
	rm -rf $(RISCV) riscv-isa-sim/build riscv-tests/build
	make -C buildroot clean

.PHONY: gcc vmlinux images help fw_payload.bin uImage alsaqr.dtb

help:
	@echo "usage: $(MAKE) [tool/img] ..."
	@echo ""
	@echo "install compiler with"
	@echo "    make gcc"
	@echo ""
	@echo "install [tool] with compiler"
	@echo "    where tool can be any one of:"
	@echo "        gcc isa-sim tests"
	@echo ""
	@echo "build linux images for cva6"
	@echo "        make images"
	@echo "    for specific artefact"
	@echo "        make [vmlinux|uImage|fw_payload.bin]"
	@echo ""
	@echo "There are two clean targets:"
	@echo "    Clean only build object"
	@echo "        make clean"
	@echo "    Clean everything (including toolchain etc)"
	@echo "        make clean-all"
