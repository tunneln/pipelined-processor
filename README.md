## Pipelined Processor



##instruction set

  encoding          instruction   description

  0000iiiiiiiitttt  mov i,t       regs[t] = i; pc += 1;
  0001aaaabbbbtttt  add a,b,t     regs[t] = regs[a] + regs[b]; pc += 1;
  0010jjjjjjjjjjjj  jmp j         pc = j;
  0011000000000000  halt          <stop fetching instructions>
  0100iiiiiiiitttt  ld i,t        regs[t] = mem[i]; pc += 1;
  0101aaaabbbbtttt  ldr a,b,t     regs[t] = mem[regs[a]+regs[b]]; pc += 1;
  0110aaaabbbbtttt  jeq a,b,t     if (regs[a] == regs[b]) pc += d
                                  else pc += 1;
  0111aaaassssssss  st s,a        mem[s] = regs[a]; pc += 1;

## To compile and run
~~~~~~~~~~
    make & make run
~~~~~~
### To test
~~~~~~~
    make test
