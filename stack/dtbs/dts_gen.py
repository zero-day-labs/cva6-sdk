#!/usr/bin/env python3

import sys
import fileinput

CPU_TARGET="""CPUhartid: cpu@hartid {
      device_type = "cpu";
      status = "okay";
      compatible = "eth,ariane", "riscv";
      clock-frequency = <targetfreq>;
      riscv,isa = "rv64fimadch";
      mmu-type = "riscv,sv39";
      tlb-split;
      reg = <hartid>;
      CPUhartid_intc: interrupt-controller {
        #address-cells = <1>;
        #interrupt-cells = <1>;
        interrupt-controller;
        compatible = "riscv,cpu-intc";
      };
    };
"""

CLINT="""    clint@2000000 {
      compatible = "riscv,clint0";
      interrupts-extended = all-interrupts;
      reg = <0x0 0x2000000 0x0 0xc0000>;
      reg-names = "control";
    };
"""
PLIC="""PLIC0: interrupt-controller@c000000 {
      #address-cells = <0>;
      #interrupt-cells = <1>;
      compatible = "riscv,plic0";
      interrupt-controller;
      interrupts-extended = all-interrupts;
      reg = <0x0 0xc000000 0x0 0x4000000>;
      riscv,max-priority = <7>;
      riscv,ndev = <255>;
    };
"""
APLICM="""   APLICM: interrupt-controller@c000000 {
       riscv,delegate = <&APLICS 0x01 0x60>;
       riscv,children = <&APLICS>;
       riscv,num-sources = <0x60>;
       reg = <0x00 0xc000000 0x00 0x8000>;
       irqc-mode = all-interrupts;
       interrupt-controller;
       #interrupt-cells = <0x02>;
       compatible = "riscv,aplic";
     };
"""
APLICS="""APLICS: interrupt-controller@d000000 {
      riscv,num-sources = <0x60>;
      reg = <0x00 0xd000000 0x00 0x8000>;
      interrupts-extended = all-interrupts;
      interrupt-controller;
      #interrupt-cells = <0x02>;
      compatible = "riscv,aplic";
    };
"""
IMSICM="""    IMSICM: interrupt-controller@24000000 {
			riscv,ipi-id = <0x01>;
			riscv,num-ids = <255>;
			reg = <0x00 0x24000000 0x00 0x2000>;
			interrupts-extended = all-interrupts;
			msi-controller;
			interrupt-controller;
			#interrupt-cells = <0x01>;
			compatible = "riscv,imsics";
		};
"""
IMSICS="""     IMSICS: interrupt-controller@28000000 {
      riscv,guest-index-bits = <1>;
			riscv,ipi-id = <0x01>;
			riscv,num-ids = <255>;
			reg = <0x00 0x28000000 0x00 0x4000>;
			interrupts-extended = all-interrupts;
			msi-controller;
			interrupt-controller;
			#interrupt-cells = <0x01>;
			compatible = "riscv,imsics";
		};
"""
DEBUG="""    debug-controller@0 {
      compatible = "riscv,debug-013";
      interrupts-extended = all-interrupts;
      reg = <0x0 0x0 0x0 0x1000>;
      reg-names = "control";
    };
"""

TIMER= """    timer@18000000 {
      compatible = "pulp,apb_timer";
      interrupts = intp-timer;
      reg = <0x00000000 0x18000000 0x00000000 0x00001000>;
      interrupt-parent = irqc;
      reg-names = "control";
    };
"""
UART = """    uart@40000000 {
      compatible = "ns16550";
      reg = <0x0 0x40000000 0x0 0x1000>;
      clock-frequency = <targetfreq>;
      current-speed = <targetbaud>;
      interrupt-parent = irqc;
      interrupts = intp-uart;
      reg-shift = <2>; // regs are spaced on 32 bit boundary
      reg-io-width = <4>; // only 32-bit access are supported
    };
"""
def replace_strings(file_path, old_string, new_string):
    with fileinput.FileInput(file_path, inplace=True) as file:
        for line in file:
            print(line.replace(old_string, new_string), end='')

if __name__ == "__main__":
    if len(sys.argv) != 8:
        print("Usage: python3 dts_gen.py <file-path> <num_harts> <target-freq> <half-freq> <target-baud> <minimal> <irqc>")
        sys.exit(1)
    
    # Extract command-line arguments
    file_path = sys.argv[1]
    num_harts = sys.argv[2]
    minimal = sys.argv[6]
    irqc = sys.argv[7]

    cpus = ""
    clint_interrupts = ""
    plic_interrupts = ""
    aplic_m_interrupts = ""
    aplic_s_interrupts = ""
    dbg_interrupts = ""
    mem_size = "0x20000000"

    for i in range(int(num_harts)):
        cpus = cpus + "    " + CPU_TARGET.replace("hartid",str(i))
        clint_interrupts = f"{clint_interrupts} <&CPU{i}_intc 3 &CPU{i}_intc 7> "
        
        plic_interrupts = f"{plic_interrupts} <&CPU{i}_intc 11 &CPU{i}_intc 9> "
        aplic_m_interrupts = f"{aplic_m_interrupts} <&CPU{i}_intc 11> "
        aplic_s_interrupts = f"{aplic_s_interrupts} <&CPU{i}_intc 9> "

        dbg_interrupts = f"{dbg_interrupts} <&CPU{i}_intc 65535> "
        if(i!=int(num_harts)-1):
            clint_interrupts = clint_interrupts + ","

            plic_interrupts = plic_interrupts + ","
            aplic_m_interrupts = aplic_m_interrupts + ","
            aplic_s_interrupts = aplic_s_interrupts + ","
            
            dbg_interrupts = dbg_interrupts + ","
    
    clint = CLINT.replace("all-interrupts",clint_interrupts)
    debug= DEBUG.replace("all-interrupts",dbg_interrupts)
    
    if (irqc == "plic"):
      timer = TIMER.replace("irqc","<&PLIC0>")
      timer = timer.replace("intp-timer","<0x00000004 0x00000005 0x00000006 0x00000007>")
      uart = UART.replace("irqc","<&PLIC0>")
      uart = uart.replace("intp-uart","<2>")
      plic = PLIC.replace("all-interrupts",plic_interrupts)
    elif (irqc == "aplic"):
      timer = TIMER.replace("irqc","<&APLICS>")
      timer = timer.replace("intp-timer","<0x00000004 0x4 0x00000005 0x4 0x00000006 0x4 0x00000007 0x4>")
      uart = UART.replace("irqc","<&APLICS>")
      uart = uart.replace("intp-uart","<2 0x4>")
      aplic_m = APLICM.replace("irqc-mode","interrupts-extended")
      aplic_s = APLICS.replace("irqc-mode","interrupts-extended")
      aplic_m = aplic_m.replace("all-interrupts",aplic_m_interrupts)
      aplic_s = aplic_s.replace("all-interrupts",aplic_s_interrupts)
    elif (irqc == "aia"):
      timer = TIMER.replace("irqc","<&APLICS>")
      timer = timer.replace("intp-timer","<0x00000004 0x4 0x00000005 0x4 0x00000006 0x4 0x00000007 0x4>")
      uart = UART.replace("irqc","<&APLICS>")
      uart = uart.replace("intp-uart","<2 0x4>")
      aplic_m = APLICM.replace("irqc-mode","msi-parent")
      aplic_s = APLICS.replace("irqc-mode","msi-parent")
      aplic_m = aplic_m.replace("all-interrupts","<&IMSICM>")
      aplic_s = aplic_s.replace("all-interrupts","<&IMSICS>")
      imsic_m = IMSICM.replace("all-interrupts",aplic_m_interrupts)
      imsic_s = IMSICS.replace("all-interrupts",aplic_s_interrupts)

    if (irqc == "plic"):
      peripherals = plic
    elif (irqc == "aplic"):
      peripherals = aplic_s
      if (minimal != 'y'):
        peripherals += aplic_m
    elif (irqc == "aia"):
      peripherals = aplic_s
      peripherals += imsic_s
      if (minimal != 'y'):
        peripherals += imsic_m
        peripherals += aplic_m

    if (minimal == 'y'):
      peripherals += uart
      mem_size = "0x10000000"
    else:
      peripherals += clint+debug+timer+uart


    replace_strings(file_path,"target_cpus",cpus)
    replace_strings(file_path,"ariane_peripherals",peripherals)
    replace_strings(file_path,"targetfreq",sys.argv[3])
    replace_strings(file_path,"halffreq",sys.argv[4])
    replace_strings(file_path,"targetbaud",sys.argv[5])
    replace_strings(file_path,"mem-size",mem_size)
