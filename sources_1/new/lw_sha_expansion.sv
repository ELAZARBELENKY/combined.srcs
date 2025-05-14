//*
//*  Copyright © 2024 FortifyIQ, Inc.
//*
//*  All Rights Reserved.
//*
//*  All information contained herein is, and remains, the property of FortifyIQ, Inc.
//*  Dissemination of this information or reproduction of this material, in any medium,
//*  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
//*
//*

`timescale 1ns / 1ps
import lw_sha_pkg::*;
`include "defines.v"
(*dont_touch = "true"*)
module lw_sha_expansion (
`ifdef CORE_ARCH_S64
                          input mode,
`endif
                          input [3:0] round_index,
                          input [`WORD_SIZE-1:0] w[15:0],
                          output [`WORD_SIZE-1:0] expanded_word);

  logic [`WORD_SIZE-1:0] s0,s1;
`ifdef CORE_ARCH_S64
  assign s0 = right_rotate(w[(round_index-15)%16],mode?6'd1:6'd7,mode)^
              right_rotate(w[(round_index-15)%16],mode?6'd8:6'd18,mode)^
              (mode?(w[(round_index-15)%16]>>3'd7):{3'b0,w[(round_index-15)%16][`WORD_SIZE/2-1:3]});
                 
  assign s1 = right_rotate(w[(round_index-2)%16],mode?6'd19:6'd17,mode)^
              right_rotate(w[(round_index-2)%16],mode?6'd61:6'd19,mode)^
              (mode?(w[(round_index-2)%16]>>3'd6):{10'b0,w[(round_index-2)%16][`WORD_SIZE/2-1:10]});
`else `ifdef CORE_ARCH_S32
  assign s0 = right_rotate(w[(round_index-15)%16], 5'd7) ^
              right_rotate(w[(round_index-15)%16], 5'd18) ^
              (w[(round_index-15)%16] >> 2'h3);

  assign s1 = right_rotate(w[(round_index-2)%16], 5'd17) ^
              right_rotate(w[(round_index-2)%16], 5'd19) ^
              (w[(round_index-2)%16] >> 4'ha);
`endif `endif
  assign expanded_word = (w[round_index] + s0 + w[(round_index-7)%16] + s1);
  
endmodule
