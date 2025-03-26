//*
//*  Copyright � 2024 FortifyIQ, Inc.
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

`ifdef CORE_ARCH_S64
  localparam logic [3:0] padding_one [6]= '{4'd7,4'd8,4'd7,4'd9,4'd11,4'd12};
  localparam logic [63:0] length_field [6]= '{64'h300,64'h2e0,64'h600,64'h580,64'h500,64'h4e0};
`endif

module lw_hmac ( input clk_i,
                 input aresetn_i,
                 input start_i,
                 input abort_i,
                 input last_i,
                 input data_valid_i,
                 input [`WORD_SIZE-1:0] data_i,
                 input [1:0] random_i,
`ifdef CORE_ARCH_S64
                 input [3:0] opcode_i,
`else `ifdef CORE_ARCH_S32
                 input [1:0] opcode_i,
`endif `endif
                 input [`WORD_SIZE-1:0] key_i,
                 input key_valid_i,
                 output logic key_ready_o,
                 output logic [`WORD_SIZE-1:0] hash_o[7:0],
                 output logic ready_o ,
                 output logic core_ready_o,
                 output logic done_o,
                 output logic fault_inj_det_o = 1'b0);


  logic [3:0] counter = 4'b0;
`ifdef CORE_ARCH_S64
  logic [2:0] mode = 3'b0;
  logic s64;
`else `ifdef CORE_ARCH_S32
  logic mode = 1'b0;
`endif `endif
  logic [`WORD_SIZE-1:0] key_reg[15:0] = '{default: '0};
  logic [`WORD_SIZE-1:0] sha_output[7:0];
  logic [`WORD_SIZE-1:0] inner_hashed[7:0] = '{default: '0};;
  logic done_hash, hmac;
  logic inner_hash = 1'b0, fb = 1'b0;
  logic hash_ready;
  typedef enum logic [1:0] {not_active = 2'b00, sha_op = 2'b01, hmac_op = 2'b10} state;
  state ns, ps = not_active;

  logic hmac_last, hmac_data_valid, hmac_start = 1'b0;
  logic [`WORD_SIZE-1:0] hmac_data;

  lw_sha_main hashing ( .aresetn_i(aresetn_i),
                        .clk_i(clk_i),
                        .start_i(hmac_start||start_i),
                        .abort_i(abort_i),
                        .last_i(hmac ? hmac_last : last_i),
                        .data_valid_i(hmac ? hmac_data_valid : data_valid_i),
                        .data_i(hmac ? hmac_data : data_i),
                        .random_i(random_i),
                        .opcode_i(ps==hmac_op ? mode : opcode_i),
                        .hash_o(sha_output),
                        .ready_o(hash_ready),
                        .core_ready_o(),
                        .done_o(done_hash));
//////////////////////////////////////////////////////////////////////////////////////////////

  assign hmac_last = inner_hash?last_i&&!fb:!fb;
  assign hmac_data_valid = inner_hash && !done_hash ? (fb ? key_valid_i : data_valid_i) : 1'b1;
  assign hmac = ns == hmac_op;
`ifdef CORE_ARCH_S64
  assign s64 = mode[2]||mode[1];
  always_comb begin
    if (inner_hash) hmac_data = fb ? key_i ^ {16{8'h36}} : data_i;
    else if (fb) hmac_data = key_reg[counter];
    else begin
      if (counter[3]) begin
        if (s64) hmac_data = inner_hashed[counter[2:0]];
        else if (counter%2==0) hmac_data = inner_hashed[4+counter[2:0]/2];
        else hmac_data = inner_hashed[4+counter[2:0]/2][`WORD_SIZE-1:`WORD_SIZE/2];
      end else hmac_data = 64'h0;
      if (counter == padding_one[mode]) begin
        if (mode == 5) hmac_data = inner_hashed[4]|64'h80000000;
        else hmac_data[s64 ? 63:31] = 1'b1;
      end else if (counter == 0) hmac_data = length_field[mode];
    end
  end
`else `ifdef CORE_ARCH_S32
  assign hmac_data = inner_hash ? (fb?key_i^{8{8'h36}}:data_i):
                      fb ? key_reg[counter]:
                      counter == (mode?8:7) ? 32'h80000000:
                      counter==0 ? mode?32'h2e0:32'h300:
                      counter[3] ? inner_hashed[counter[2:0]] : 32'b0;
`endif `endif

  always_comb begin
    case (ps)
      hmac_op: begin
        if (done_hash && !inner_hash || abort_i) begin
          ns = not_active;
          key_ready_o = 0;
          ready_o = 0;
        end else begin
          key_ready_o = inner_hash && fb;
          ns = hmac_op;
          ready_o = !fb && !done_hash && inner_hash ? hash_ready : 1'b0;
        end
      end
      not_active: begin
        if (start_i && data_valid_i) begin
`ifdef CORE_ARCH_S64
          if (opcode_i[3]) begin
`else `ifdef CORE_ARCH_S32
          if (opcode_i[1]) begin
`endif `endif
            ns = hmac_op;
          end else begin
            ns = sha_op;
          end
        end else begin
          ns = not_active;
        end
        key_ready_o = 0;
        ready_o = 0;
      end
      sha_op: begin
        if (done_hash || abort_i) begin
          ns = not_active;
          key_ready_o = 0;
          ready_o = 0;
        end else begin
          ns = sha_op;
          key_ready_o = 1'b0;
          ready_o = hash_ready;
        end
      end
      default: begin
        key_ready_o = 1'b0;
        ns = not_active;
        ready_o = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge aresetn_i) begin
    if (!aresetn_i) begin
      core_ready_o <= 1'b0;
      ps <= not_active;
      fb <= 1'b0;
      inner_hash <= 1'b0;
      counter <= 4'h0;
      inner_hashed <= '{default: '0};
      mode <= 'b0;
      key_reg <= '{default: '0};
      hmac_start <= 1'b0;
      hash_o <= '{default: '0};
      done_o <= 1'b0;
    end else begin
      core_ready_o <= ns == not_active;
      ps <= ns;
      if (ps == hmac_op && (hash_ready || fb && inner_hash)) begin
        if (inner_hash) begin
          hmac_start <= 1'b1;
          if(key_valid_i) begin
            if (counter == 4'b0) begin
              fb <= 1'b0;
            end else begin
              counter <= counter - 1;
            end
          end
`ifdef CORE_ARCH_S64
          if (fb) key_reg[counter] <= key_i^{16{8'h5c}};
`else `ifdef CORE_ARCH_S32
          if (fb) key_reg[counter] <= key_i^{8{8'h5c}};
`endif `endif
          if (done_hash) begin
            inner_hash <= 1'b0;
            inner_hashed <= sha_output;
            fb <= 1'b1;
            counter <= 4'hf;
          end
        end else begin
          if (counter == 4'b0) begin
            fb <= 1'b0;
            key_reg <= '{default: '0};
          end
          hmac_start <= 1'b0;
          counter <= counter - 1;
          if (done_hash && !abort_i) begin
            hash_o <= sha_output;
            done_o <= 1'b1;
          end
        end
      end else if (ps==not_active) begin
        hmac_start <= 1'b0;
        inner_hash <= 1'b1;
        fb <= 1'b1;
        counter <= 4'hf;
        done_o <= 1'b0;
        mode <= opcode_i;
`ifdef CORE_ARCH_S64
        if (opcode_i [2:1] == 2'b11) ps <= not_active;
`endif
      end else if (ps == sha_op && done_hash && !abort_i) begin
        done_o <= 1'b1;
        hash_o <= sha_output;
      end
    end
  end
 endmodule
