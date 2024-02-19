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
PLATFORM := fpga/alsaqr
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

# default make flags
isa-sim-mk              = -j$(NR_CORES)
tests-mk         		= -j$(NR_CORES)
buildroot-mk       		= -j$(NR_CORES)

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

$(RISCV)/vmlinux: $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig) $(CC)
	mkdir -p $(RISCV)
	make -C buildroot $(buildroot-mk)
	cp buildroot/output/images/vmlinux $@

$(RISCV)/Image: $(RISCV)/vmlinux
	$(OBJCOPY) -O binary -R .note -R .comment -S $< $@

# OpenSBI with u-boot as payload
$(RISCV)/fw_payload.bin: $(RISCV)/Image
	make -C opensbi FW_PAYLOAD_PATH=$< $(sbi-mk)
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin

# specific recipes
gcc: $(CC)
vmlinux: $(RISCV)/vmlinux
fw_payload.bin: $(RISCV)/fw_payload.bin

images: $(CC) $(RISCV)/fw_payload.bin $(RISCV)/uImage

alsaqr.dtb:
	make -C opensbi $(sbi-mk) alsaqr.dts
	dtc -I dts opensbi/platform/$(PLATFORM)/fdt_gen/alsaqr.dts -O dtb -o $@

clean:
	rm -rf $(RISCV)/vmlinux cachetest/*.elf rootfs/cachetest.elf
	rm -rf $(RISCV)/fw_payload.bin $(RISCV)/uImage $(RISCV)/Image.gz
	make -C u-boot clean
	make -C opensbi distclean

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
