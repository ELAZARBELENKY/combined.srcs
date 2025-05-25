`timescale 1ns / 1ps

`include "defines.v"  
//parameter FIQSHA_FIFO_SIZE = 4;
//parameter FIQSHA_BUS_DATA_WIDTH = `FIQSHA_BUS;

module lw_sha_ahb_top #(
  parameter DATA_WIDTH = `WORD_SIZE
)(
  input  logic                     hclk,
  input  logic                     hresetn,
  input  logic [31:0]              haddr,
  input  logic [2:0]               hburst,
//  input  logic                     hmastlock,
//  input  logic [3:0]               hprot,
  input  logic [2:0]               hsize,
  input  logic [1:0]               htrans,
  input  logic [FIQSHA_BUS_DATA_WIDTH-1:0] hwdata,
  input  logic                     hwrite,
  output logic [FIQSHA_BUS_DATA_WIDTH-1:0] hrdata,
  output logic                     hreadyout,
  output logic                     hresp,
  input  logic                     hready,
  // Interrupt request
  output logic                     irq_o,
  // Optional HMAC extension
`ifdef HMACAUXKEY
  input  logic [`KEY_SIZE-1:0]    aux_key_i,
`endif
  // Random input
  input  logic [3:0]               random_i,
  // DMA support
  output logic                     dma_wr_req_o,
  output logic                     dma_rd_req_o
);
  logic                     hmastlock;///////////////////////////
  logic [3:0]               hprot;///////////////////////////////
  // Internal signals
  logic                           key_ready, key_valid;
  logic [`WORD_SIZE-1:0]          key;
  logic                           con_wr, con_wr_ack;
  logic                           con_rd, con_rd_ack;
  logic                           con_slv_error;
  logic [11:0]                    con_waddr, con_raddr;
  logic [FIQSHA_BUS_DATA_WIDTH-1:0] con_wdata, con_rdata;

  ahb_slave_adapter #(
    .DATA_WIDTH(FIQSHA_BUS_DATA_WIDTH),
    .ADDR_WIDTH(12)
  ) u_ahb_slv (
    .hclk(hclk),
    .hresetn(hresetn),
    .haddr(haddr),
    .hburst(hburst),
//    .hmastlock(hmastlock),
//    .hprot(hprot),
    .hsize(hsize),
    .htrans(htrans),
    .hwdata(hwdata),
    .hwrite(hwrite),
    .hrdata(hrdata),
    .hreadyout(hreadyout),
    .hresp(hresp),
    .hready(hready),
    // Conduit signals
    .con_wr(con_wr),
    .con_wr_ack(con_wr_ack),
    .con_rd(con_rd),
    .con_rd_ack(con_rd_ack),
    .con_waddr(con_waddr),
    .con_raddr(con_raddr),
    .con_wdata(con_wdata),
    .con_rdata(con_rdata),
    .con_slverr(con_slv_error)
  );

logic start, abort, last, valid, ready, fault_inj_det, core_ready, done;
logic [3:0] opcode;
logic [DATA_WIDTH-1:0] data;
logic [DATA_WIDTH-1:0] hash[7:0];
logic core_reset;
logic new_key;
logic con_rd_ff;

always_ff @(posedge hclk)
  if (!hresetn)
    con_rd_ff <= 1'b0;
  else if (con_rd)
    con_rd_ff <= 1'b1;
  else
    con_rd_ff <= 1'b0;

lw_sha_interface_control_logic #(
   .FIQSHA_BUS_DATA_WIDTH(FIQSHA_BUS_DATA_WIDTH),
   .ARCH_SZ(DATA_WIDTH)
) u_if_core (
   .clk_i(hclk),
   .resetn_i(hresetn),
   .wr_i(con_wr),
   .wr_ack_o(con_wr_ack),
   .rd_i(con_rd_ff),
   .rd_ack_i(con_rd_ack),
   .waddr_i(con_waddr),
   .raddr_i(con_raddr),
   .wdata_i(con_wdata),
   .rdata_o(con_rdata),
   .read_valid_o(),
`ifdef HMACAUXKEY
   .aux_key_i(aux_key_i),
`endif
   .burst_type_i(hburst),
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
   .core_reset_o(core_reset),
   .overflow(1'b0)
);

lw_hmac u_lw_hmac_core (
   .clk_i(hclk),
   .aresetn_i(core_reset && hresetn),
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

endmodule: lw_sha_ahb_top
