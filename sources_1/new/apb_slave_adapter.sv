//*
//*  Copyright (c) 2024 FortifyIQ, Inc.
//*
//*  All Rights Reserved.
//*
//*  All information contained herein is, and remains, the property of FortifyIQ, Inc.
//*  Dissemination of this information or reproduction of this material, in any medium,
//*  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
//*

module APB_slave_adapter #(
  parameter byte D_WIDTH = 32
) (
    input pclk
  , input presetn
  , input [11:0] paddr
  , input psel
  , input penable
  , input pwrite
  , input [D_WIDTH-1:0] pwdata
  , input [D_WIDTH/8-1:0] pstrb
  , output logic pready
  , output logic [D_WIDTH-1:0] prdata
  , output pslverr
  // conduit connectivity
  , output con_wr
  , input con_wr_ack
  , output reg con_rd
  , output con_rd_ack
  , output [11:0] con_waddr
  , output [11:0] con_raddr
  , output [D_WIDTH-1:0] con_wdata
  , output [D_WIDTH/8-1:0] con_wbyte_enable
  , output [D_WIDTH/8-1:0] con_rbyte_enable
  , input [D_WIDTH-1:0] con_rdata
  , input con_read_valid
  , input con_slv_error
);

  assign pslverr = con_slv_error & penable & psel;

  assign con_waddr = paddr[11:0];
  assign con_raddr = paddr[11:0];
  assign con_wdata = pwdata;
  assign con_wbyte_enable = pstrb;
  assign con_rbyte_enable = '1;
  assign con_wr = psel & ~penable & pwrite;
  assign con_rd = psel & ~penable & ~pwrite;
  assign con_rd_ack = con_read_valid;

  always_ff @(posedge pclk) begin
    prdata <= con_rdata;
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      pready <= 1'b0;
    end else begin
      pready <= con_wr_ack | con_read_valid | con_slv_error;
    end
  end

endmodule