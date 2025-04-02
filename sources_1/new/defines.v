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
