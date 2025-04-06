`timescale 1ns / 1ps
  //Address map
  localparam ID_ADDR   = 12'h000;
  localparam CFG_ADDR  = 12'h010;
  localparam CTL_ADDR  = 12'h020;
  localparam STS_ADDR  = 12'h030;
  localparam IE_ADDR   = 12'h040;
  localparam HASH_ADDR = 12'h100;
  localparam DIN_ADDR  = 12'h140;
  localparam SEED_ADDR = 12'h300;

module lw_sha_interface_control_logic #(
   parameter int FIQSHA_BUS_DATA_WIDTH = 32,
   parameter int FIQSHA_FIFO_SIZE = 4,
//   parameter int BYTE_MAP_SZ = 2048,
   parameter int ARCH_SZ = `WORD_SIZE,
   parameter bit INCLUDE_PRNG = 0,
//   parameter bit BURST_EN = 0,
//   parameter bit BYTE_ACCESS_EN = 0,
   parameter logic [31:0] ID_VAL = 32'h0)
   (
   input clk_i,                                      // clock signal
   input resetn_i,                                    // reset,
   input wr_i,                                        // write from bus interface adapter
   output reg wr_ack_o,                               // write ackowledge to bus interface adapter
   input rd_i,                                        // read request from bus interface adapter
   input rd_ack_i,                                    // read ack from bus interface adapter
   input [11:0] waddr_i,                              // write address
   input [11:0] wtransaction_cnt_i,
   input [11:0] raddr_i,                              // read adress
   input [11:0] rtransaction_cnt_i,
   input [FIQSHA_BUS_DATA_WIDTH-1:0] wdata_i,         // write data
   input [FIQSHA_BUS_DATA_WIDTH/8-1:0] wbyte_enable_i,// write data bytes strobs
   input [FIQSHA_BUS_DATA_WIDTH/8-1:0] rbyte_enable_i,// read data bytes strobs
   output reg [FIQSHA_BUS_DATA_WIDTH-1:0] rdata_o,    // read data
   output reg read_valid_o,                           // read data validation strob
//   input read_ready_i,                                // ready for read from a bus interface adapter
   input [255:0] aux_key_i, // dedicated key port to protected secret input instead bus transaction.
//   input wstuck_i,
//   input rstuck_i,
   input [1:0] burst_type_i,
   output irq_o,
  // native interface
   input [`WORD_SIZE-1:0] hash_i[7:0],
   input ready_i,
   input core_ready_i,
   input done_i,
   input fault_inj_det_i,
   output [`WORD_SIZE-1:0] data_o,
   output start_o,
   output abort_o,
   output last_o,
   output [3:0] opcode_o,
   output logic valid_o,
   
   output dma_wr_req_o,
   output dma_rd_req_o,
   output slv_error_o,
   output core_reset_o
   );
   
  logic [31:0] id_reg = ID_VAL;
  logic [31:0] cfg_reg, ctl_reg, sts_reg, ie_reg, seed_reg, din_reg;
  logic [8*`WORD_SIZE-1:0] hash_reg;
//  logic fifo_fixed_transaction;
//  logic block_fixed_wtransaction_incr;
//  logic block_fixed_rtransaction_incr;
//  logic wr_less_than_bus_width;
//  logic rd_less_than_bus_width;

  logic init_ack, last_ack, abort_ack;
//        avl_clr, rdy_clr,
//        derr_clr, busy_clr, faultinjdet_clr, keyunlocked_clr,
//        avl_set, rdy_set, derr_set, busy_set,
//        faultinjdet_set, keyunlocked_set;
  localparam DIN_SIZE = `WORD_SIZE*4;
  localparam HASH_ADDR = 12'h100;
  localparam HASH_SIZE = `WORD_SIZE*8;

  always_ff @(posedge clk_i or negedge resetn_i) begin
    if (~resetn_i) begin
      cfg_reg <= '0;
      ctl_reg <= '0;
      sts_reg[5] <= 1'b0;
      ie_reg <= 32'h2;
      seed_reg <= '0;
    end else begin
      if (wr_i) begin
        case (waddr_i)
          CFG_ADDR: begin
            cfg_reg <= {wdata_i[31], 18'h0, wdata_i[12:8], 1'b0, wdata_i[6:0]};
          end
          CTL_ADDR: begin
            ctl_reg[31:0] <= {29'h0, wdata_i[2:0]};
//            if (wdata_i[0]) ctl_reg[0] <= 1'b1;
            valid_o <= wr_i && core_ready_i;
          end
          STS_ADDR: begin
            if (wdata_i[5]) sts_reg[5] <= 1'b0;
            if (wdata_i[2]) sts_reg[2] <= 1'b0;
          end
//          SEED_ADDR: begin
//            if (`FIQSHA_PRNG_INIT == "SW")
//              seed_reg <= wdata_i[31:0];
//            else
//              seed_reg <= {31'h0, wdata_i[0]};
//          end
          DIN_ADDR: begin
//            if (ready_i) begin
              din_reg <= wdata_i;
              valid_o <= wr_i;
//            end
          end
          default:;
        endcase
//        if (abort_ack)
//          ctl_reg[2] <= 1'b0;
//        if (last_ack)
//          ctl_reg[1] <= 1'b0;
//        if (init_ack)
//          ctl_reg[0] <= 1'b0;
        if (cfg_reg[31]) begin
          cfg_reg <= '0;
          ctl_reg <= '0;
          sts_reg <= 32'h2;
          ie_reg <= 32'h2;
        end
//      end
      end else valid_o <= 0;
    end
  end
  
  wire [$clog2(HASH_SIZE/8)-$clog2(FIQSHA_BUS_DATA_WIDTH/8)-1:0] hash_reg_word_rptr = 
    raddr_i[$clog2(HASH_SIZE/8)-1:$clog2(FIQSHA_BUS_DATA_WIDTH/8)];
    
  always_ff @(posedge clk_i or negedge resetn_i) begin
    if (!resetn_i) begin
    rdata_o <= 32'h0;
//    end else if (rd_i) begin
//      read_valid_o <= 1'b1;
      case (raddr_i)
        CFG_ADDR: rdata_o <= cfg_reg;
        CTL_ADDR: rdata_o <= ctl_reg;
        STS_ADDR: rdata_o <= sts_reg;
        IE_ADDR: rdata_o <= ie_reg;
//        HASH_ADDR: rdata_o <= hash_reg;
        default:
          if (raddr_i[11:$clog2(HASH_SIZE/8)] === HASH_ADDR[11:$clog2(HASH_SIZE/8)]) begin
            for (int i = 0; i < HASH_SIZE/FIQSHA_BUS_DATA_WIDTH; i++) begin
              if (i === hash_reg_word_rptr)
                rdata_o = hash_reg[i*FIQSHA_BUS_DATA_WIDTH +: FIQSHA_BUS_DATA_WIDTH];
            end
          end
      endcase
//     else read_valid_o <= 1'b0;
    end
  end
  assign hash_reg = {hash_i[7],hash_i[6],hash_i[5],hash_i[4],hash_i[3],hash_i[2],hash_i[1],hash_i[0]};
  assign sts_reg[4:0] = {fault_inj_det_i, core_ready_i, 1'b0, ready_i, done_i};
  assign start_o = ctl_reg[0];
  assign last_o = ctl_reg[1];
  assign abort_o = ctl_reg[2];
  assign opcode_o = cfg_reg[3:0];
  assign data_o = din_reg;
//  always_ff @(posedge clk_i)  wr_ack_o = ready_i;
  assign wr_ack_o = ready_i;
  assign slv_error_o = 0;
  assign core_reset_o = !cfg_reg[31];
  assign read_valid_o = rd_i;
//  assign valid_o = (waddr_i==DIN_ADDR|| waddr_i==CTL_ADDR&& core_ready_i)&&wr_i;
//  assign HMACUSEINTKEY_o = cfg_reg[4];
//  assign HMACAUXKEY_o = cfg_reg[5];
//  assign HMACSAVEKEY_o = cfg_reg[6];
endmodule
