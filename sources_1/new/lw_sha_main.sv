//*
//*  Copyright � 2024 FortifyIQ, Inc.
//*
//*  All Rights Reserved.
//*
//*  All information contained herein is, and remains, the property of FortifyIQ, Inc.
//*  Dissemination of this information or reproduction of this material, in any medium,
//*  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
//*

`timescale 1ns / 1ps
import lw_sha_pkg::*;
`include "defines.v"
(*dont_touch = "true"*)
module lw_sha_main( input clk_i,
                    input aresetn_i,
                    input start_i,
                    input abort_i,
                    input last_i,
                    input data_valid_i,
                    input [`WORD_SIZE-1:0] data_i,
                    input [$clog2(`WORD_SIZE)*2-1:0] random_i,
`ifdef CORE_ARCH_S64
                    input [2:0] opcode_i,
`else `ifdef CORE_ARCH_S32
                    input opcode_i,
`endif `endif
                    output logic [`WORD_SIZE-1:0] hash_o[7:0],
                    output logic ready_o,
                    output logic core_ready_o,
                    output logic done_o);
  logic [`WORD_SIZE-1:0] w[15:0] = '{default:'0};
  logic [`WORD_SIZE-1:0] word, expanded_word;
  logic [`WORD_SIZE+$clog2(`WORD_SIZE)-1:0] state[7:0] = '{default:'0};
  logic [`WORD_SIZE+$clog2(`WORD_SIZE)-1:0] new_state[7:0];
  logic [`WORD_SIZE-1:0] initial_state[7:0] = '{default:'0};
  logic [6:0] round_index = '{default:'0};
  logic finish = 1'b0;
  logic proccess_is_active;
`ifdef CORE_ARCH_S64
  logic [2:0] mode = 3'b000;
  logic s64;
`else `ifdef CORE_ARCH_S32
  logic mode = 1'b0;
`endif `endif
  typedef enum logic {not_active=1'b0, active=1'b1} status;
  status ns, ps = not_active;

  //instantiations
  // Round calculation
  lw_sha_round round (
`ifdef CORE_ARCH_S64
  .mode(s64),
`endif
  .word(word),
  .state(state),
  .round_index(round_index),
  .random_i(random_i),
  .new_state(new_state)
  );

  // Message schedule expansion
  lw_sha_expansion expand (
`ifdef CORE_ARCH_S64
  .mode(s64),
`endif
  .round_index(round_index[3:0]),
  .w(w),
  .expanded_word(expanded_word)
  );

  always_comb begin
    case (ps)
      not_active: begin
        ready_o = 0;
        if (start_i && data_valid_i && core_ready_o) begin
          ns = active;
        end else begin
          ns = not_active;
        end
      end
      active: begin
`ifdef CORE_ARCH_S64
        if (round_index == (s64 ? 'd81 : 'd65) || abort_i) begin
          ready_o = s64 ? 'd81 : 'd65;
`else `ifdef CORE_ARCH_S32
          if (round_index == 7'd65 || abort_i) begin
          ready_o = round_index == 7'd65;
`endif `endif
          ns = not_active;
        end else begin
          ns = active;
          ready_o = round_index[6:4]==3'b000;
        end
      end
      default: begin
        ns = not_active;
        ready_o = 1'b1;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge aresetn_i) begin
    if (!aresetn_i) begin
      core_ready_o <= 1'b0;
      ps <= not_active;
      w <= '{default:'0};
      hash_o <= '{default:'0};
      initial_state <= '{default:'0};
      state <= '{default:'0};
      round_index <= 'b0;
      finish <= 1'b0;
      mode <= 'b0;
      done_o <= 1'b0;
    end else begin
      core_ready_o <= ns == not_active;
      ps <= ns;
      if (proccess_is_active) begin
`ifdef CORE_ARCH_S64
        if (round_index == (s64 ? 'd80 : 'd64 )) begin
`else `ifdef CORE_ARCH_S32
        if (round_index == 7'd64) begin
`endif `endif
          if (finish) begin
            round_index <= round_index + 7'b1;
            done_o <= 1'b1;
            finish <= 1'b0;
`ifdef CORE_ARCH_S64
            hash_o <= '{default:'0};
            if (s64) begin
              for (int i = 0; i < 8; i++) begin
                if (i>=(mode[2]?4:mode[0]?2:0)) begin
                  hash_o[i] <= initial_state[i] + read_word(state[i],s64);
                end
              end
            end else begin
              for (int i = 0; i < 8; i++) begin
                if (i%2==0) begin
                  hash_o[i/2+4]<=initial_state[i] + read_word(state[i],s64);
                end else begin
                  hash_o[i/2+4][`WORD_SIZE-1:`WORD_SIZE/2]<=
                  initial_state[i] + read_word(state[i],s64);
                end
              end
            end
            if (mode==5||mode==1) begin
              hash_o[4][`WORD_SIZE/2-1:0] <= 32'b0;
            end
          end else begin
            round_index <= 'b0;
            foreach (initial_state[i]) begin
              initial_state[i] <= initial_state[i] + read_word(state[i],s64);
              state[i] <= {initial_state[i] + read_word(state[i],s64)};/////////////////////////
            end
          end
`else `ifdef CORE_ARCH_S32
            foreach (hash_o[i]) hash_o[i] <= initial_state[i] + read_word(state[i]);
            if (mode) hash_o[0] <= '0;
          end else begin
            round_index <= 'b0;
            foreach (initial_state[i]) begin
              initial_state[i] <= initial_state[i] + read_word(state[i]);
              state[i] <= {initial_state[i] + read_word(state[i])};/////////////////////////
            end
          end
`endif `endif
        end else begin
          done_o <= 1'b0;
          w[round_index[3:0]] <= word;
          state <= new_state;
          round_index <= round_index + 7'b1;
          if (round_index[6:4] == 3'b000) begin
            if (last_i) finish <= 1'b1;
          end
        end
      end else if (ps==not_active) begin
        finish <= 1'b0;
        done_o <= 1'b0;
        round_index <= 'b0;
        mode <= opcode_i;
`ifdef CORE_ARCH_S64
        if (opcode_i [2:1] == 2'b11) ps <= not_active;
        initial_state <= standard_initial_state[opcode_i];
        foreach (state[i]) state[i] <= standard_initial_state[opcode_i][i];
`else `ifdef CORE_ARCH_S32
        initial_state <= opcode_i ? standard_initial_state224:standard_initial_state256;
        foreach (state[i])
        state[i] <= opcode_i ? standard_initial_state224[i]:standard_initial_state256[i];
`endif `endif
      end else done_o <= 1'b0;
    end
  end
  
`ifdef CORE_ARCH_S64
  assign s64 = mode[2]||mode[1];
`endif
  assign word = round_index[6:4]== 3'b000 ? data_i : expanded_word; 
  assign proccess_is_active = (ps==active)&&
  (data_valid_i || round_index[6:4]!=3'h0);
endmodule
