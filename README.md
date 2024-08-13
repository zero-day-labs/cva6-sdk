# CVA6-based SoC SDK - AlSaqr Platform
This repository contains instructions to generate and run various images to validate the correct functioning of the AlSaqr exploratory path (integration of the AIA, IOMMU, and IOPMP IPs).   

## :warning: Important
1. The steps in this README have been validated in 6.1.92-1-MANJARO and UBUNTU 20.04.
2. All the generated images have been validated in the He-SoC `zdl/exp-path` [branch](https://github.com/AlSaqr-platform/he-soc/commits/zdl/exp-path/), commit `fbe19ecadee90bf788071c943ff8e0e230adc2ed`

## Quickstart

```console
$ git clone git@github.com:D3boker1/cva6-sdk.git
$ git checkout zdl/exp-path
$ git submodule update --init --recursive
```

## Platform Specific Macros

| Macro            	| Default  	| Description                                  	|
|------------------	|----------	|----------------------------------------------	|
| XLEN             	| 64       	| System register width                        	|
| PLAT             	| alsaqr   	| Sets the target platform                     	|
| PLAT_TARGET_FREQ 	| 40000000 	| Target frequency (only in alsaqr)            	|
| PLAT_NUM_HARTS   	| 2        	| Target number of cores (only in alsaqr)      	|
| PLAT_IRQC        	| plic     	| Target interrupt controller (only in alsaqr) 	|


## Images Generation
The following steps will guide you through the generation of different output images encompassing various software stacks for the AlSaqr platform. Additionally, you can find guidelines to load these images into AlSaqr implemented in the VCU118 FPGA board.

### Tools
Run the following command to generate the linux GCC compiler.

```console
$ make gcc
```

### Basic Tests
Run the following command to generate basic images to test AIA, IOMMU, or IOPMP IPs.

```console
$ make tests-<aia|iommu|iopmp>
```
### Baremetal
Run the following command to generate a Baremetal image with AIA and IOMMU support.

```console
$ make baremetal BARE=1 PLAT=alsaqr PLAT_IRQC=aia
```

### Linux
Run the following command to generate a Linux image with AIA and IOMMU support.

```console
$ make linux PLAT=alsaqr PLAT_IRQC=aia
```

### Bao + Baremetal
Run the following command to generate a Bao + Baremetal image with AIA and IOMMU support.

```console
$ make bao BAO-GUEST=baremetal BARE=1 PLAT=alsaqr PLAT_IRQC=aia
```

### Bao + Linux
Run the following command to generate a Bao + Baremetal image with AIA and IOMMU support.

```console
$ make bao BAO-GUEST=linux PLAT=alsaqr PLAT_IRQC=aia
```

### More Info
If the presented steps are not what you want, you can get help by making:

```console
$ make help
```

## Run the Images on VCU118
To run the generated images on VCU118 FPGA follow the steps:

1. Open Vivado Hardware Manager and flash the AlSaqr bitstream
2. Open 3 terminals
3. On terminal one open the ttyUSB<#> with your prefered tool (we used gtkterm and screen)
4. On terminal two type:
  ```console
  $ openocd -f /scripts/openocd-dual-core.cfg
  ```
5. On terminal three type:
  ```console
  $ riscv64-buildroot-linux-gnu-gdb install64/<payload-name>.elf -x /scripts/gdb-dual-core.cfg
  ```
6. We should see messages being printed on terminal one