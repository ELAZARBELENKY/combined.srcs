//*
//*  Copyright (c) 2024 FortifyIQ, Inc.
//*
//*  All Rights Reserved.
//*
//*  All information contained herein is, and remains, the property of FortifyIQ, Inc.
//*  Dissemination of this information or reproduction of this material, in any medium,
//*  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
//*
`include "defines.v"
module lw_sha_apb_top (
	 pclk,
	 presetn,
	 paddr,
	 psel,
	 penable,
	 pwrite,
	 pwdata,
	 pready,
	 prdata,
	 pslverr,
	// interrupt request
	 irq_o,
	// extensions
	 aux_key_i,
   random_i,
  // DMA support
   dma_wr_req_o,
   dma_rd_req_o
);

  parameter FIQSHA_FIFO_SIZE = 4;
  parameter FIQSHA_BUS_DATA_WIDTH = 32;
  
  localparam DATA_WIDTH = `WORD_SIZE;

  input pclk;
  input presetn;
  input [11:0] paddr;
  input psel;
  input penable;
  input pwrite;
  input [FIQSHA_BUS_DATA_WIDTH-1:0] pwdata;
  output pready;
  output [FIQSHA_BUS_DATA_WIDTH-1:0] prdata;
  output pslverr;
  // interrupt request
  output irq_o;
  // extensions
  input [255:0] aux_key_i;
  input logic [1:0] random_i;
  // DMA support
  output dma_wr_req_o;
  output dma_rd_req_o;

logic con_wr, con_wr_ack, con_rd, con_rd_ack, con_read_valid, con_slv_error;
logic [11:0] con_waddr, con_raddr;
logic [FIQSHA_BUS_DATA_WIDTH-1:0] con_wdata, con_rdata;

APB_slave_adapter
// #(
//    .D_WIDTH(FIQSHA_BUS_DATA_WIDTH)
//)
 u_apb_slv (
   .pclk(pclk),
   .presetn(presetn),
   .paddr(paddr),
   .psel(psel),
   .penable(penable),
   .pwrite(pwrite),
   .pwdata(pwdata),
   .pstrb('1),
   .pready(pready),
   .prdata(prdata),
   .pslverr(pslverr),
  // conduit connectivity
   .con_wr(con_wr),
   .con_wr_ack(con_wr_ack),
   .con_rd(con_rd),
   .con_rd_ack(con_rd_ack),
   .con_waddr(con_waddr),
   .con_raddr(con_raddr),
   .con_wdata(con_wdata),
   .con_wbyte_enable(),
   .con_rbyte_enable(),
   .con_rdata(con_rdata),
   .con_read_valid(con_read_valid),
   .con_slv_error(con_slv_error)
);

logic start, abort, last, valid, ready, fault_inj_det, core_ready, done;
logic [3:0] opcode;
logic [DATA_WIDTH*8-1:0] state, state_share2, state_share3;
logic [DATA_WIDTH-1:0] data;
logic [DATA_WIDTH-1:0] hash[7:0];
logic core_reset;

interface_control_logic #(
   .FIQSHA_BUS_DATA_WIDTH(FIQSHA_BUS_DATA_WIDTH),
   .FIQSHA_FIFO_SIZE(FIQSHA_FIFO_SIZE),
   .BYTE_MAP_SZ(2048),
   .ARCH_SZ(DATA_WIDTH),
   .INCLUDE_PRNG(0),
   .BURST_EN(0),
   .BYTE_ACCESS_EN(0)
) u_if_core (
   .clk_i(pclk),
   .resetn_i(presetn),
   .wr_i(con_wr),
   .wr_ack_o(con_wr_ack),
   .rd_i(con_rd),
   .rd_ack_i(con_rd_ack),
   .waddr_i(con_waddr),
   .wtransaction_cnt_i('0),
   .raddr_i(con_raddr),
   .rtransaction_cnt_i('0),
   .wdata_i(con_wdata),
   .wbyte_enable_i('1),
   .rbyte_enable_i('1),
   .rdata_o(con_rdata),
   .read_valid_o(con_read_valid),
   .read_ready_i('1),
   .aux_key_i(aux_key_i),
   .wstuck_i('0),
   .rstuck_i('0),
   .burst_type_i('0),
   .new_write_transaction_i('0),
   .wtransaction_active_i('0),
   .new_read_transaction_i('0),
   .rtransaction_active_i('0),
   .irq_o(irq_o),
  // native interface
   .start_o(start),
   .abort_o(abort),
   .last_o(last),
   .opcode_o(opcode),
   .data_o(data),
   .hash_i(hash),
   .valid_o(valid),
   .ready_i(ready),
   .core_ready_i(core_ready),
   .done_i(done),
   .fault_inj_det_i(fault_inj_det),
   .dma_wr_req_o(dma_wr_req_o),
   .dma_rd_req_o(dma_rd_req_o),
   .slv_error_o(con_slv_error),
   .core_reset_o(core_reset)
);
logic key_valid_i = 1;
logic key_ready_o;
logic [31:0] key;
logic [3:0] ctr = 0;

  always_ff @(posedge pclk) begin
    if (start) ctr <= 0;
    else if (key_ready_o&&key_valid_i) begin
      key <= aux_key_i[ctr*31-:32];
      ctr <= ctr + 1;
    end
  end

lw_hmac u_lw_hmac_core (
   .clk_i(pclk),
   .aresetn_i(core_reset),
   .start_i(start),
   .abort_i(abort),
   .last_i(last),
   .data_valid_i(valid),
   .key_i(key),
   .key_valid_i(key_valid_i),
   .key_ready_o(key_ready_o),
   .ready_o(ready),
   .opcode_i(opcode),
   .data_i(data),
   .random_i(random_i),
   .hash_o(hash),
   .core_ready_o(core_ready),
   .done_o(done),
   .fault_inj_det_o(fault_inj_det)
);

endmodule: lw_sha_apb_top