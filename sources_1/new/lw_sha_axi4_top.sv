localparam DATA_WIDTH = `FIQSHA_BUS;

module lw_sha_axi4_top (
  input  logic                  aclk,
  input  logic                  aresetn,

  // Write address channel
  input  logic [11:0]           awaddr,
  input  logic [7:0]            awlen,
  input  logic [2:0]            awsize,
  input  logic [1:0]            awburst,
  input  logic                  awvalid,
  input  logic [3:0]            awid,
  output logic                  awready,

  // Write data channel
  input  logic [DATA_WIDTH-1:0] wdata,
  input  logic                  wlast,
  input  logic                  wvalid,
  output logic                  wready,

  // Write response channel
  output logic [1:0]            bresp,
  output logic                  bvalid,
  input  logic                  bready,

  // Read address channel
  input  logic [11:0]           araddr,
  input  logic [7:0]            arlen,
  input  logic [2:0]            arsize,
  input  logic [1:0]            arburst,
  input  logic                  arvalid,
  output logic                  arready,

  // Read data channel
  output logic [DATA_WIDTH-1:0] rdata,
  output logic [1:0]            rresp,
  output logic                  rlast,
  output logic                  rvalid,
  input  logic                  rready,
  // IRQ
  output logic irq,                   // Interrupt request
  output logic dma_rd_req_o,
  output logic dma_wr_req_o,
  input [1:0] random_i
`ifdef HMACAUXKEY
  ,input [`KEY_SIZE-1:0] aux_key_i
`endif
);
logic ready, core_ready, key_ready;
logic con_slv_error, con_read_valid, con_wr, con_rd, con_rd_ack;
logic [11:0] con_raddr, con_waddr;
logic [`FIQSHA_BUS-1:0] con_rdata, con_wdata;
logic reject_data;
logic overflow;
always_ff @(posedge aclk) begin
  if (awvalid) begin
    con_slv_error <= 1'b0;
    if (awaddr == KEY_ADDR) begin
      reject_data <= !key_ready;
    end else if (awaddr == DIN_ADDR) begin
      reject_data <= !ready;
    end
  end else if (con_wr) begin
    case (awaddr)
      CFG_ADDR: con_slv_error <= !core_ready;
      CTL_ADDR: con_slv_error <= 0;
      STS_ADDR: con_slv_error <= !(wdata[0] || wdata[3]);
      IE_ADDR:  con_slv_error <= 0;
      DIN_ADDR: begin
        con_slv_error <= reject_data;
        if (!reject_data && !ready) overflow <= 1'b1;
      end
      KEY_ADDR: begin
        con_slv_error <= reject_data;
        if (!reject_data && !key_ready) overflow <= 1'b1;
      end
    endcase
  end else begin
    overflow <= 1'b0;
    reject_data <= 1'b0;
  end
end

  // AXI4 Slave Adapter instance
  axi4_slave_adapter #(
    .D_WIDTH(`FIQSHA_BUS),            // Data width
    .AXI_A_WIDTH(12),                 // AXI address width
    .CON_A_WIDTH(12)                  // Conduit address width
  ) axi4_inst (
    .aclk(aclk),
    .aresetn(aresetn),
    // AXI4 interface signals
    .awaddr(awaddr),
    .awlen(awlen),
    .awsize(awsize),
    .awburst(awburst),
    .awvalid(awvalid),
    .awready(awready),
    .awid(awid),
    .wdata(wdata),
    .wlast(wlast),
    .wvalid(wvalid),
    .wready(wready),
    .wstrb('1),
    .araddr(araddr),
    .arlen(arlen),
    .arsize(arsize),
    .arburst(arburst),
    .arvalid(arvalid),
    .arready(arready),
    .rdata(rdata),
    .rresp(rresp),
    .rlast(rlast),
    .rvalid(rvalid),
    .rready(rready),
    .bresp(bresp),
    .bvalid(bvalid),
    .bready(bready),
    // Conduit interface signals
    .break_transaction(1'b0),
    .con_read_valid(con_read_valid),
    .con_wr(con_wr),
    .con_rd(con_rd),
    .con_rd_ack(con_rd_ack),
    .con_overflow(1'b0),
    .con_waddr(con_waddr),
    .con_raddr(con_raddr),
    .con_wdata(con_wdata),
    .con_rdata(con_rdata),
    .con_ready_for_read(1'b1),
    .con_slv_error(con_slv_error)
  );
logic start, abort, last, valid, fault_inj_det, done;
logic [3:0] opcode;
logic [`WORD_SIZE-1:0] data;
logic [`WORD_SIZE-1:0] hash[7:0];
logic core_reset;
logic new_key, key_valid;
logic [`WORD_SIZE-1:0] key;

  // HMAC Control Logic instance
  lw_sha_interface_control_logic #(
    .FIQSHA_BUS_DATA_WIDTH(`FIQSHA_BUS),       // Data width
    .ARCH_SZ(`WORD_SIZE)                      // Word size
  ) hmac_ctrl (
    .clk_i(aclk),
    .resetn_i(aresetn),
    // Bus interface signals
    .wr_i(con_wr),
//    .wr_ack_o(wr_ack),
    .rd_i(con_rd),
//    .rd_ack_i(rd_ack),
    .waddr_i(con_waddr),
    .raddr_i(con_raddr),
    .wdata_i(con_wdata),
    .rdata_o(con_rdata),
//    .rdata_o(rdata),
    .read_valid_o(con_read_valid),
    .rd_ack_i(con_rd_ack),
    .slv_error_o(),
    // Native HMAC signals
`ifdef HMACAUXKEY
    .aux_key_i(aux_key_i),
`endif
    .key_valid_o(key_valid),
    .key_ready_i(key_ready),
    .start_o(start),
    .valid_o(valid),
    .key_o(key),
    .data_o(data),
    .opcode_o(opcode),
    .done_i(done),
    .hash_i(hash),
    .ready_i(ready),
    .last_o(last),
    .new_key_o(new_key),
    .core_ready_i(core_ready),
    .abort_o(abort),
    .fault_inj_det_i(fault_inj_det),
    .irq_o(irq),
    .core_reset_o(core_reset),
    .overflow(overflow),
    .dma_wr_req_o(dma_wr_req_o),
    .dma_rd_req_o(dma_rd_req_o)
  );

lw_hmac u_lw_hmac_core (
   .clk_i(aclk),
   .aresetn_i(core_reset || aresetn),
   .start_i(start),
   .abort_i(abort),
   .last_i(last),
   .data_valid_i(valid && (!reject_data||start)),
   .key_i(key),
   .key_valid_i(key_valid && !reject_data),
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

endmodule