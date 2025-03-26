//*
//*  Copyright c 2024 FortifyIQ, Inc.
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
module lw_sha_round (
`ifdef CORE_ARCH_S64
                     input mode,
`endif
                     input [`WORD_SIZE-1:0] word,
                     input [`WORD_SIZE+1:0] state [7:0],
                     input [6:0] round_index,
                     input [3:0] random_i,
                     output logic [`WORD_SIZE+1:0] new_state [7:0]);

  logic [`WORD_SIZE-1:0] delta_a, delta_e, temp1 ,temp2, choice, majority, sum0, sum1;
  logic [`WORD_SIZE-1:0] a, b, c, e, f, g;
  logic [1:0] random_a, random_e;
  assign random_a = random_i[1:0];
  assign random_e = random_i[3:2];
`ifdef CORE_ARCH_S64
  assign a = read_word(state[7],mode);
  assign b = read_word(state[6],mode);
  assign c = read_word(state[5],mode);
  assign e = read_word(state[3],mode);
  assign f = read_word(state[2],mode);
  assign g = read_word(state[1],mode);

  assign choice = (e & f) ^ (~e & g);
  assign majority = (a & b) ^ (a & c) ^ (b & c);
  assign sum0 = right_rotate(a,mode?6'd28:6'd2,mode)^
                right_rotate(a,mode?6'd34:6'd13,mode)^
                right_rotate(a,mode?6'd39:6'd22,mode);
                
  assign sum1 = right_rotate(e,mode?6'd14:6'd6,mode)^
                right_rotate(e,mode?6'd18:6'd11,mode)^
                right_rotate(e,mode?6'd41:6'd25,mode);
  assign temp1 = read_word(state[0],mode) + sum1 + choice +
         (mode ? k512[round_index]:k256[round_index]) + word;
  assign temp2 = sum0 + majority;

  assign delta_a = temp1 + temp2;
  assign delta_e = temp1 + read_word(state[4],mode);

  assign new_state[7] = write_word(delta_a, random_a, mode); //assigning a
  assign new_state[3] = write_word(delta_e, random_e, mode); //assigning e
  assign new_state[6:4] = state[7:5]; //assigning b,c,d (to be previous-state's a,b,c)
  assign new_state[2:0] = state[3:1]; //assigning f,g,h (to be previous-state's e,f,g)
`else `ifdef CORE_ARCH_S32
  assign a = read_word(state[7]);
  assign b = read_word(state[6]);
  assign c = read_word(state[5]);
  assign e = read_word(state[3]);
  assign f = read_word(state[2]);
  assign g = read_word(state[1]);

  assign choice = (e & f) ^ (~e & g);
  assign majority = (a & b) ^ (a & c) ^ (b & c);
  assign sum0 = right_rotate(a, 5'd2) ^ right_rotate(a, 5'd13) ^ right_rotate(a, 5'd22);
  assign sum1 = right_rotate(e, 5'd6) ^ right_rotate(e, 5'd11) ^ right_rotate(e, 5'd25);
  assign temp1 = read_word(state[0]) + sum1 + choice + k[round_index] + word;
  assign temp2 = sum0 + majority;

  assign delta_a = temp1 + temp2;
  assign delta_e = temp1 + read_word(state[4]);

  assign new_state[7] = write_word(delta_a, random_a); //assigning a
  assign new_state[3] = write_word(delta_e, random_e); //assigning e
  
//  assign new_state[7] = {random_a, right_rotate(delta_a, random_a)}; //assigning a
//  assign new_state[3] = {random_e, right_rotate(delta_a, random_a)}; //assigning e
  
  assign new_state[6:4] = state[7:5]; //assigning b,c,d (to be previous-state's a,b,c)
  assign new_state[2:0] = state[3:1]; //assigning f,g,h (to be previous-state's e,f,g)
`endif `endif
endmodule
