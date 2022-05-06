# CVA6 SDK

This repository houses a set of RISCV tools for the [CVA6 core](https://github.com/openhwgroup/cva6). Most importantly it **does not contain openOCD**.

Included tools:
* [Spike](https://github.com/riscv/riscv-isa-sim/), the ISA simulator
* [riscv-tests](https://github.com/riscv/riscv-tests/), a battery of ISA-level tests
* [riscv-fesvr](https://github.com/riscv/riscv-fesvr/), the host side of a simulation tether that services system calls on behalf of a target machine
* [u-boot](https://github.com/AlSaqr-platform/u-boot/)
* [opensbi](https://github.com/riscv/opensbi/), the open-source reference implementation of the RISC-V Supervisor Binary Interface (SBI)

To fetch them:
```console
git submodule update --init --recursive
```

## Setup

Requirements Ubuntu:
```console
$ sudo apt-get install autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev libusb-1.0-0-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev device-tree-compiler pkg-config libexpat-dev
```

Requirements Fedora:
```console
$ sudo dnf install autoconf automake @development-tools curl dtc libmpc-devel mpfr-devel gmp-devel libusb-devel gawk gcc-c++ bison flex texinfo gperf libtool patchutils bc zlib-devel expat-devel
```

To properly build the U-Boot and Linux binaries, you first have to export some variables:
```console
export ARCH=riscv
export CROSS_COMPILE=riscv64-unknown-linux-gnu-
export RISCV=<path-to-your-riscv-toolchain>
export PATH=$RISCV/bin:$PATH
````

## Linux

### Boot flow
Linux boot-flow is supported on the VCU118 leveraging the state-of-the-art U-Boot tool and follow the following steps:

0. OPEN-OCD + GDB work as zero stage bootloader. Through JTAG we load U-BOOT-SPL and change the register a1 to pass the dtb's address to U-BOOT-SPl
1. U-BOOT-SPL, stored in the L2SPM, loads OPEN-SBI (`fw_dynamic`) and U-BOOT-SPL from the VCU118's SPI FLASH into the DDR4 and jumps to OPEN-SBI
2. U-BOOT in S-mode sets up the environment for the linux kernel, loads the linux kernel from the SPI FLASH into the DDR4 and then launches it
3. Linux kernel starts

### Binaries generation

```bash
$ make u-boot/u-boot.itb 
$ make uImage
```

### FPGA Setup + Launch

The first command generates U-BOOT-SPL and OPEN-SBI + U-BOOT. The second one generates the Linux kernel image in U-BOOT format. To launch Linux we need: `u-boot/spl/u-boot-spl`, `u-boot/u-boot.itb` and `uImage`.
The last two need to be loaded in the SPI FLASH, to do so, open Vivado HW Manager and add to the board a configuration memory device, `mt25qu01g-spi-x1_x2_x4` in our case. Then, generate the `.mcs` files to load:

```
write_cfgmem -force -format mcs -size 256 -interface SPIx4 -loaddata "up 0x6000000 u-boot/u-boot.itb" -file "ubootitb.mcs"
write_cfgmem -force -format mcs -size 256 -interface SPIx4 -loaddata "up 0x6100000 uImage           " -file "uImage.mcs"
```

Program the configuration memory device with the two files. We now can load U-BOOT-SPL and run it:

```
$ riscv64-unknown-elf-gdb ~/spi/u-boot-spl
   GNU gdb (GDB) 10.1
   Copyright (C) 2020 Free Software Foundation, Inc.
   License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
   This is free software: you are free to change and redistribute it.
   There is NO WARRANTY, to the extent permitted by law.
   Type "show copying" and "show warranty" for details.
   This GDB was configured as "--host=x86_64-pc-linux-gnu --target=riscv64-unknown-elf".
   Type "show configuration" for configuration details.
   For bug reporting instructions, please see:
   <https://www.gnu.org/software/gdb/bugs/>.
   Find the GDB manual and other documentation resources online at:
       <http://www.gnu.org/software/gdb/documentation/>.
   
   For help, type "help".
   Type "apropos word" to search for commands related to "word"...
   Reading symbols from /home/pulpone/spi/u-boot-spl5...
(gdb) target remote :3333
   Remote debugging using :3333
   0x0000000000010000 in ?? ()
(gdb) monitor reset halt
   JTAG tap: riscv.cpu tap/device found: 0x20001001 (mfg: 0x000 (<invalid>), part: 0x0001, ver: 0x2)
(gdb) load
   Loading section .text, size 0x71d4 lma 0x1c000000
   Loading section .rodata, size 0x2b60 lma 0x1c0071d8
   Loading section .data, size 0xd98 lma 0x1c009d38
   Loading section .got, size 0x160 lma 0x1c00aad0
   Loading section .u_boot_list, size 0xaa0 lma 0x1c00ac30
   Loading section .binman_sym_table, size 0x10 lma 0x1c00b6d0
   Start address 0x000000001c000000, load size 46812
   Transfer rate: 51 KB/sec, 6687 bytes/write.
(gdb) set $a1 = 0x1C040000
(gdb) c
```

On another terminal compile the dts and launch openocd (which will load the dtb to `0x1C040000`:
```console
dtc -I dts ./u-boot/arch/riscv/dts/occamy.dts -O dtb -o occamy.dtb
sudo /home/pulpone/riscv-openocd/src/openocd -f zcu-102-ariane.cfg
```

We'll align the dtb name and platform name to the correct one ASAP. We also plan to eventually remove JTAG+OPENOCD as zero stage boot-loader :)
