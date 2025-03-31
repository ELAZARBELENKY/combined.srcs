`include "../../sources_1/new/interfaces.sv"
`include "../../sources_1/new/enviroment.sv"
`include "../../sources_1/new/tests.sv"

`timescale 1ns / 1ps

module interface_control_logic_tb;

  logic [255:0] aux_key_i;
  logic clk = 0;

  native_if_t native_if(clk);
  slave_adapter_if_t slv_bus_if(clk);
  apb_if #(.D_WIDTH(`WORD_SIZE)) apb(clk);

  initial begin
    for (int i = 0; i < 64; i++)
      aux_key_i[i*4+:4] = 4'ha;
    slv_bus_if.resetn = 1'b0;
    apb.presetn = 1'b0;
    @(posedge clk);
    slv_bus_if.resetn = 1'b1;
    apb.presetn = 1'b1;
  end

  always #5 clk <= ~clk;
  logic irq_o;
  logic dma_wr_req_o, dma_rd_req_o;


  tests test1(
      .native_if(native_if.slv)
    , .slv_bus_if(slv_bus_if.mst)
    , .apb(apb.mst)
  );

  if (`TEST == 0) begin
    interface_control_logic #(
        // .FIQSHA_BUS_DATA_WIDTH(32)
        .FIQSHA_FIFO_SIZE(4)
      // , .SLICE_SZ(32)
      // , .BYTE_MAP_SZ(1024)
      , .ARCH_SZ(`ARCH_SZ)
      // , .INCLUDE_PRNG(0)
      // , .BURST_EN(0)
      // , .BYTE_ACCESS_EN(0)
    ) dut (
        .clk_i(slv_bus_if.clk)
      , .resetn_i(slv_bus_if.resetn)
      , .wr_i(slv_bus_if.wr)
      , .wr_ack_o(slv_bus_if.wr_ack)
      , .rd_i(slv_bus_if.rd)
      , .rd_ack_i(slv_bus_if.rd_ack)
      , .waddr_i(slv_bus_if.waddr)
      , .wtransaction_cnt_i(slv_bus_if.wtransaction_cnt)
      , .raddr_i(slv_bus_if.raddr)
      , .rtransaction_cnt_i(slv_bus_if.rtransaction_cnt)
      , .wdata_i(slv_bus_if.wdata)
      , .wbyte_enable_i(slv_bus_if.wbyte_enable)
      , .rbyte_enable_i(slv_bus_if.rbyte_enable)
      , .rdata_o(slv_bus_if.rdata)
      , .read_valid_o(slv_bus_if.read_valid)
      , .read_ready_i(slv_bus_if.read_ready)
      , .aux_key_i(aux_key_i)
      , .wstuck_i(slv_bus_if.wstuck)
      , .rstuck_i(slv_bus_if.rstuck)
      , .burst_type_i(slv_bus_if.burst_type)
      , .new_write_transaction_i(slv_bus_if.new_write_transaction)
      , .wtransaction_active_i(slv_bus_if.wtransaction_active)
      , .new_read_transaction_i(slv_bus_if.new_read_transaction)
      , .rtransaction_active_i(slv_bus_if.rtransaction_active)
      , .irq_o(irq_o)
      // native interface
      , .start_o(native_if.start)
      , .abort_o(native_if.abort)
      , .last_o(native_if.last)
      , .opcode_o(native_if.opcode)
      , .data_o(native_if.data)
      , .hash_i(native_if.hash)
      , .valid_o(native_if.valid)
      , .ready_i(native_if.ready)
      , .core_ready_i(native_if.core_ready)
      , .done_i(native_if.done)
      , .fault_inj_det_i(native_if.fault_inj_det)
      , .dma_wr_req_o()
      , .dma_rd_req_o()
      , .slv_error_o()
    );
  end else begin
    lw_sha_apb_top dut (
        .pclk(apb.pclk)
      , .presetn(apb.presetn)
      , .paddr(apb.paddr[11:0])
      , .psel(apb.psel)
      , .penable(apb.penable)
      , .pwrite(apb.pwrite)
      , .pwdata(apb.pwdata)
      , .pready(apb.pready)
      , .prdata(apb.prdata)
      , .pslverr(apb.pslverr)
      // interrupt request
//      , .irq(irq_o)
      // extensions
      , .aux_key_i(aux_key_i)
      , .random_i('0)
      // DMA support
      , .dma_wr_req_o(dma_wr_req_o)
      , .dma_rd_req_o(dma_rd_req_o)
    );
  end



endmodule : interface_control_logic_tb