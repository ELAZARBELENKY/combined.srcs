`define CORE_ARCH_S64

`ifdef CORE_ARCH_S32
   `define WORD_SIZE 32
  `else `ifdef CORE_ARCH_S64
   `define WORD_SIZE 64
`endif `endif