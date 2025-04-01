/*
 *  Copyright (c) 2025 FortifyIQ, Inc.
 *
 *  All Rights Reserved.
 *
 *  All information contained herein is, and remains, the property of FortifyIQ, Inc.
 *  Dissemination of this information or reproduction of this material, in any medium,
 *  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
 *
 */

`define CORE_ARCH_S32
`define FIQLIB__ASYNC_RST

`ifdef CORE_ARCH_S32
   `define WORD_SIZE 32
  `else `ifdef CORE_ARCH_S64
   `define WORD_SIZE 64
`endif `endif

`ifndef FIQLIB__DEFINES
`define FIQLIB__DEFINES

  `define FIQLIB__RENAME_MACRO_FROM_TO(__old, __new) \
    `ifdef __new                                     \
    $warning(`"Macro ``__new has been redefined`");  \
    `endif                                           \
    `define __new `__old

  // Synchronous reset FF or asynchronous reset FF depending on a macro
  `ifndef FF
    `ifdef FIQLIB__ASYNC_RST
      `define FF(clk, rst) always_ff @(``clk or ``rst)
    `elsif FIQLIB__SYNC_RST
      `define FF(clk, rst) always_ff @(``clk)
    `else
      $error("Neither FIQLIB__ASYNC_RST nor FIQLIB__SYNC_RST macro is defined");
    `endif
  `endif

  // Synchronous reset FF
  `ifndef FFSR
    `define FFSR(clk) always_ff @(``clk)
  `endif

`endif