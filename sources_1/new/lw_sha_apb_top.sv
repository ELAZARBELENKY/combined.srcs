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
	 pstrb,
	 pready,
	 prdata,
	 pslverr,
	// interrupt request
	 irq_o,
	// extensions
`ifdef HMACAUXKEY
  aux_key_i,
`endif
   random_i,
  // DMA support
   dma_wr_req_o,
   dma_rd_req_o
);

  parameter FIQSHA_FIFO_SIZE = 4;
  parameter FIQSHA_BUS_DATA_WIDTH = `FIQSHA_BUS;
  
  localparam DATA_WIDTH = `WORD_SIZE;

  input pclk;
  input presetn;
  input [11:0] paddr;
  input psel;
  input penable;
  input pwrite;
  input [FIQSHA_BUS_DATA_WIDTH-1:0] pwdata;
  input [FIQSHA_BUS_DATA_WIDTH/8-1:0] pstrb;
  output pready;
  output [FIQSHA_BUS_DATA_WIDTH-1:0] prdata;
  output pslverr;
  // interrupt request
  output irq_o;
  // extensions
`ifdef HMACAUXKEY
  input [`KEY_SIZE-1:0] aux_key_i;
`endif
  input logic [1:0] random_i;
  // DMA support
  output dma_wr_req_o;
  output dma_rd_req_o;
  
logic key_ready, key_valid;
logic [`WORD_SIZE-1:0] key;
logic con_wr, con_wr_ack, con_rd, con_rd_ack, con_read_valid, con_slv_error;
logic [11:0] con_waddr, con_raddr;
logic [FIQSHA_BUS_DATA_WIDTH-1:0] con_wdata, con_rdata;


 apb_slave_adapter
 #(
    .D_WIDTH(FIQSHA_BUS_DATA_WIDTH)
)
 u_apb_slv (
   .pclk(pclk),
   .presetn(presetn),
   .paddr(paddr),
   .psel(psel),
   .penable(penable),
   .pwrite(pwrite),
   .pwdata(pwdata),
   .pstrb(pstrb),
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
logic [DATA_WIDTH-1:0] data;
logic [DATA_WIDTH-1:0] hash[7:0];
logic core_reset;
logic new_key;

lw_sha_interface_control_logic #(
   .FIQSHA_BUS_DATA_WIDTH(FIQSHA_BUS_DATA_WIDTH),
   .FIQSHA_FIFO_SIZE(FIQSHA_FIFO_SIZE),
//   .BYTE_MAP_SZ(2048),
   .ARCH_SZ(DATA_WIDTH),
   .INCLUDE_PRNG(0)
//   .BURST_EN(0),
//   .BYTE_ACCESS_EN(0)
) u_if_core (
   .clk_i(pclk),
   .resetn_i(presetn),
   .wr_i(con_wr),
   .wr_ack_o(con_wr_ack),
   .rd_i(con_rd),
   .rd_ack_i(con_rd_ack),
   .waddr_i(con_waddr),
   .raddr_i(con_raddr),
   .wdata_i(con_wdata),
   .rdata_o(con_rdata),
   .read_valid_o(con_read_valid),
//   .read_ready_i('1),
`ifdef HMACAUXKEY
   .aux_key_i(aux_key_i),
`endif
//   .wstuck_i('0),
//   .rstuck_i('0),
   .burst_type_i('0),
//   .new_write_transaction_i('0),
//   .wtransaction_active_i('0),
//   .new_read_transaction_i('0),
//   .rtransaction_active_i('0),
   .irq_o(irq_o),
  // native interface
   .key_o(key),
   .key_valid_o(key_valid),
   .key_ready_i(key_ready),
   .start_o(start),
   .abort_o(abort),
   .last_o(last),
   .opcode_o(opcode),
   .data_o(data),
   .hash_i(hash),
   .valid_o(valid),
   .ready_i(ready),
   .new_key_o(new_key),
   .core_ready_i(core_ready),
   .done_i(done),
   .fault_inj_det_i(fault_inj_det),
   .dma_wr_req_o(dma_wr_req_o),
   .dma_rd_req_o(dma_rd_req_o),
   .slv_error_o(con_slv_error),
   .core_reset_o(core_reset)
);

lw_hmac u_lw_hmac_core (
   .clk_i(pclk),
   .aresetn_i(core_reset),
   .start_i(start),
   .abort_i(abort),
   .last_i(last),
   .data_valid_i(valid),
   .key_i(key),
   .key_valid_i(key_valid),
   .key_ready_o(key_ready),
   .ready_o(ready),
   .opcode_i(opcode),
   .data_i(data),
   .new_key_i(new_key),
   .random_i(random_i),
   .hash_o(hash),
   .core_ready_o(core_ready),
   .done_o(done),
   .fault_inj_det_o(fault_inj_det)
);

endmodule: lw_sha_apb_top