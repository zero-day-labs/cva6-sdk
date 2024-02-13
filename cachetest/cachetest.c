// Copyright 2019 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

extern int printf(const char *format, ...);

#define read_csr(reg) ({ unsigned long __tmp; \
  asm volatile ("csrr %0, " #reg : "=r"(__tmp)); \
  __tmp; })

#define write_csr(reg, val) ({ \
  asm volatile ("csrw " #reg ", %0" :: "rK"(val)); })

volatile long int buffer[1024 * 16 * 8];

void sweep(int stride)
{
  volatile long instrets_start, cycles_start, icachemiss_start, dcachemiss_start;
  volatile long levent_start, sevent_start, ifempty_start, stall_start;
  volatile long instrets, cycles, icachemiss, dcachemiss;
  volatile long levent, sevent, ifempty, stall;
  int max_j = 16 * 1024 / 8;
  int working_set = max_j * stride;

  for(int i = 0; i < 10; i++)
  {
    asm volatile("": : :"memory");     
    if(i == 1)
    {
      instrets_start   = read_csr(instret);
      cycles_start     = read_csr(cycle);
      icachemiss_start = read_csr(0xc03);
      dcachemiss_start = read_csr(0xc04);
      levent_start     = read_csr(0xc05);
      sevent_start     = read_csr(0xc06);
      ifempty_start    = read_csr(0xc07);
      stall_start      = read_csr(0xc08);
    }

    asm volatile("": : :"memory");     
    for(int j = 0; j < max_j; j++)
    {
      buffer[j] = icachemiss_start;
    }
    asm volatile("": : :"memory");    
    for(int j = 0; j < max_j; j++)
    {
      buffer[j*stride] = dcachemiss_start;
    }
    asm volatile("": : :"memory");

  }

  instrets   = read_csr(instret) - instrets_start;
  cycles     = read_csr(cycle) - cycles_start;
  icachemiss = read_csr(0xc03) - icachemiss_start;
  dcachemiss = read_csr(0xc04) - dcachemiss_start;
  levent     = read_csr(0xc05) - levent_start;
  sevent     = read_csr(0xc06) - sevent_start;
  ifempty    = read_csr(0xc07) - ifempty_start;
  stall      = read_csr(0xc08) - stall_start;

  printf("%2dKB, %ld, %ld, %f, %ld, %ld, %ld, %ld, %ld, %ld,\n", 
         working_set / 1024, instrets, cycles, (float) cycles / instrets, icachemiss, dcachemiss, levent, sevent, ifempty, stall);
}

int main()
{
  printf("working_set, instructions, cycles,    CPI, icachemiss, dcachemiss, levent, sevent, ifempty,    stall\n"); 

  sweep(0);
  sweep(1);
  sweep(2);
  sweep(4);
  sweep(8);
  sweep(16);

  return 0;
}
