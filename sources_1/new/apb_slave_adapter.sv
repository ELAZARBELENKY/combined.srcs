/*
 *  Copyright © 2025 FortifyIQ, Inc.
 *
 *  All Rights Reserved.
 *
 *  All information contained herein is, and remains, the property of FortifyIQ, Inc.
 *  Dissemination of this information or reproduction of this material, in any medium,
 *  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
 *
 */
`include "defines.v"
module apb_slave_adapter #(
    parameter int D_WIDTH        = 32,
    parameter int A_WIDTH        = 12,
    parameter bit NO_WAIT_STATES = 1   // enables transfer completion in 2 cycles
) (
    input  logic                 pclk
  , input  logic                 presetn
  , input  logic [A_WIDTH-1:0]   paddr
  , input  logic                 psel
  , input  logic                 penable
  , input  logic                 pwrite
  , input  logic [D_WIDTH-1:0]   pwdata
  , input  logic [D_WIDTH/8-1:0] pstrb
  , output logic                 pready
  , output logic [D_WIDTH-1:0]   prdata
  , output logic                 pslverr
  // conduit connectivity
  , output logic                 con_wr
  , input  logic                 con_wr_ack
  , output logic                 con_rd
  , output logic                 con_rd_ack
  , output logic [A_WIDTH-1:0]   con_waddr
  , output logic [A_WIDTH-1:0]   con_raddr
  , output logic [D_WIDTH-1:0]   con_wdata
  , output logic [D_WIDTH/8-1:0] con_wbyte_enable
  , output logic [D_WIDTH/8-1:0] con_rbyte_enable
  , input  logic [D_WIDTH-1:0]   con_rdata
  , input  logic                 con_read_valid
  , input  logic                 con_slv_error
);

  assign pslverr = con_slv_error & penable & psel;//

  logic [1:0] read_cond;
  logic [1:0] write_cond;
  logic read_valid;

  assign con_waddr = paddr;//
  assign con_raddr = paddr;//
  assign con_wdata = pwdata;//
  assign con_wbyte_enable = pstrb;//
  assign con_rbyte_enable = '1;//
  assign con_wr = write_cond[0] & !write_cond[1];//
  assign con_rd = read_cond[0] & ~read_cond[1];//
  assign con_rd_ack = read_valid;//

  assign pready = con_wr_ack || read_valid || con_slv_error;

  generate
    if (NO_WAIT_STATES) begin: l_wr_rd_comb

      always_comb begin
        write_cond[0] = psel && penable &&  pwrite;
        read_cond[0]  = psel && !penable && !pwrite;
        read_valid    = con_read_valid;
        prdata        = con_rdata;
      end

    end else begin: l_wr_rd_ff

      `FF (posedge pclk, negedge presetn) begin
        if (!presetn) begin
          write_cond[0] <= 1'b0;
          read_cond[0]  <= 1'b0;
          read_valid    <= 1'b0;
          prdata        <= '0;
        end else begin
          if (con_read_valid) begin
            prdata     <= con_rdata;
            read_valid <= 1'b1;
          end else if (con_rd_ack) begin
            read_valid <= 1'b0;
          end
          write_cond[0] <= psel && penable && pwrite;
          read_cond[0]  <= psel && penable && !pwrite;
        end
      end

    end
  endgenerate

  `FF (posedge pclk, negedge presetn) begin
    if (!presetn) begin
      read_cond[1]  <= '0;
      write_cond[1] <= '0;
    end else begin
      write_cond[1] <= write_cond[0];
      read_cond[1]  <= read_cond[0];
    end
  end

endmodule