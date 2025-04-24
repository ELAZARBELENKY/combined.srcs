`timescale 1ns / 1ps
  //Address map
  localparam ID_ADDR   = 12'h000;
  localparam CFG_ADDR  = 12'h010;
  localparam CTL_ADDR  = 12'h020;
  localparam STS_ADDR  = 12'h030;
  localparam IE_ADDR   = 12'h040;
  localparam HASH_ADDR = 12'h100;
  localparam DIN_ADDR  = 12'h140;
  localparam KEY_ADDR  = 12'h150;
  localparam SEED_ADDR = 12'h300;

module lw_sha_interface_control_logic #(
   parameter int FIQSHA_BUS_DATA_WIDTH = `FIQSHA_BUS,
   parameter int FIQSHA_FIFO_SIZE = 4,
   parameter int ARCH_SZ = `WORD_SIZE,
   parameter bit INCLUDE_PRNG = 0,
   parameter logic [31:0] ID_VAL = 32'h0)
   (
   input clk_i,
   input resetn_i,
   input wr_i,                                        // write from bus interface adapter
   output reg wr_ack_o,                               // write ackowledge to bus interface adapter
   input rd_i,                                        // read request from bus interface adapter
   input rd_ack_i,                                    // read ack from bus interface adapter
   input [11:0] waddr_i,                              // write address
   input [11:0] raddr_i,                              // read adress
   input [FIQSHA_BUS_DATA_WIDTH-1:0] wdata_i,         // write data
   output reg [FIQSHA_BUS_DATA_WIDTH-1:0] rdata_o,    // read data
   output reg read_valid_o,                           // read data validation strob
   input [FIQSHA_BUS_DATA_WIDTH/8-1:0] wbyte_enable_i,                                // ready for read from a bus interface adapter
`ifdef HMACAUXKEY
   input [`KEY_SIZE-1:0] aux_key_i, // dedicated key port to protected secret input instead bus transaction.
`endif

   input [1:0] burst_type_i,
   output irq_o,
  // native interface
   input [`WORD_SIZE-1:0] hash_i[7:0],
   input ready_i,
   input core_ready_i,
   input done_i,
   input fault_inj_det_i,
   input key_ready_i,
   output logic key_valid_o,
   output logic [`WORD_SIZE-1:0] key_o,
   output [`WORD_SIZE-1:0] data_o,
   output start_o,
   output abort_o,
   output last_o,
   output [3:0] opcode_o,
   output logic valid_o,
   
   output dma_wr_req_o,
   output dma_rd_req_o,
   output reg slv_error_o,
   output core_reset_o
   );
   
  localparam byte BUS_DATA_IN_ARCH_SZ = (ARCH_SZ + FIQSHA_BUS_DATA_WIDTH - 1)/FIQSHA_BUS_DATA_WIDTH;
  logic first_word = 1;
  logic s64;
  logic hash_avliable = 1'b0;
  logic [31:0] id_reg = ID_VAL;
  logic [31:0] cfg_reg, ctl_reg, sts_reg, ie_reg, seed_reg;
  logic [`WORD_SIZE-1:0] din_reg;
  logic [8*`WORD_SIZE-1:0] hash_reg;

  localparam HASH_SIZE = `WORD_SIZE*8;

  always_ff @(posedge clk_i or negedge resetn_i) begin
    if (~resetn_i) begin
      cfg_reg <= '0;
      ctl_reg <= '0;
      sts_reg[3] <= 1'b0;
      ie_reg <= 32'h2;
      seed_reg <= '0;
    end else begin
      if (wr_i) begin
`ifdef HMACAUXKEY
        wr_ack_o = ready_i || core_ready_i;
`else
        wr_ack_o = ready_i || key_ready_i || core_ready_i;
`endif
        case (waddr_i)
          CFG_ADDR: begin
            for (int i = 0; i < FIQSHA_BUS_DATA_WIDTH/8; i++) begin
              if (wbyte_enable_i[i]) cfg_reg[(i*8)+:8] = wdata_i[(i*8)+:8];
            end
//            cfg_reg <= {wdata_i[31], 18'h0, wdata_i[12:8], 4'b0, wdata_i[3:0]};
          end
          CTL_ADDR: begin
            if (wbyte_enable_i[0]) begin
              ctl_reg[31:0] <= {29'h0, wdata_i[2:0]};
              valid_o <= wdata_i[0] && (core_ready_i);
            end
          end
          STS_ADDR: begin
            if (wdata_i[3] && wbyte_enable_i[0]) sts_reg[3] <= 1'b0;
          end
          IE_ADDR: begin
            if (wbyte_enable_i[0]) ie_reg <= {27'h0, wdata_i[4:0]};
          end
          DIN_ADDR: begin
            if (ready_i) begin
`ifdef CORE_ARCH_S64
              if (`FIQSHA_BUS == 32 && s64) begin
                for (int i = 0; i < FIQSHA_BUS_DATA_WIDTH/8; i++) begin
                  if (wbyte_enable_i[i]) begin
                    din_reg[i*8+(first_word?FIQSHA_BUS_DATA_WIDTH:0)+:8] = wdata_i[(i*8)+:8];
                  end
                end
                valid_o <= !first_word;
                first_word <= !first_word;
              end else begin
//                din_reg <= wdata_i;
                for (int i = 0; i < FIQSHA_BUS_DATA_WIDTH/8; i++) begin
                  if (wbyte_enable_i[i]) begin
                    din_reg[i*8+:8] = wdata_i[(i*8)+:8];
                  end
                end
                valid_o <= 1'b1;
              end
`else `ifdef CORE_ARCH_S32
//              din_reg <= wdata_i;
              for (int i = 0; i < FIQSHA_BUS_DATA_WIDTH/8; i++) begin
                if (wbyte_enable_i[i]) begin
                  din_reg[i*8+:8] = wdata_i[(i*8)+:8];
                end
              end
              valid_o <= 1'b1;
`endif `endif
            end else begin
              sts_reg[3] <= 1'b1;
              slv_error_o <= 1'b1;
            end
          end
`ifndef HMACAUXKEY
          KEY_ADDR: begin
            if (key_ready_i) begin
`ifdef CORE_ARCH_S64
              if (`FIQSHA_BUS == 32 && s64) begin
                for (int i = 0; i < FIQSHA_BUS_DATA_WIDTH/8; i++) begin
                  if (wbyte_enable_i[i]) begin
                    key_o[i*8+(first_word?FIQSHA_BUS_DATA_WIDTH:0)+:8] = wdata_i[(i*8)+:8];
                  end
                end
                key_valid_o <= !first_word;
                first_word <= !first_word;
              end else begin
                for (int i = 0; i < FIQSHA_BUS_DATA_WIDTH/8; i++) begin
                  if (wbyte_enable_i[i]) begin
                    key_o[i*8+:8] = wdata_i[(i*8)+:8];
                  end
                end
                key_valid_o <= 1'b1;
              end
`else `ifdef CORE_ARCH_S32
//              key_o <= wdata_i;
              for (int i = 0; i < FIQSHA_BUS_DATA_WIDTH/8; i++) begin
                if (wbyte_enable_i[i]) begin
                  key_o[i*8+:8] = wdata_i[(i*8)+:8];
                end
              end
              key_valid_o <= 1'b1;
`endif `endif
            end else begin
              sts_reg[3] <= 1'b1;
              slv_error_o <= 1'b1;
            end
          end
`endif
          default:;
        endcase
        if (cfg_reg[31] && wbyte_enable_i[FIQSHA_BUS_DATA_WIDTH/8-1]) begin
          cfg_reg <= '0;
          ctl_reg <= '0;
          sts_reg <= 32'h2;
          ie_reg <= 32'h2;
        end
      end else begin
        slv_error_o <= 1'b0;
        wr_ack_o = 1'b0;
        if (start_o) ctl_reg[0] <= 1'b0;
        if (done_i) ctl_reg[1] <= 1'b0;
        if (abort_o) ctl_reg[2] <= 1'b0;
        valid_o <= 0;
`ifndef HMACAUXKEY
        key_valid_o <= 0;
`endif
      end
    end
  end
  
  wire [$clog2(HASH_SIZE/8)-$clog2(FIQSHA_BUS_DATA_WIDTH/8)-1:0] hash_reg_word_rptr = 
    raddr_i[$clog2(HASH_SIZE/8)-1:$clog2(FIQSHA_BUS_DATA_WIDTH/8)];
  
  always_ff @(posedge clk_i or negedge resetn_i) begin
    if (!resetn_i || start_o) hash_avliable <= 1'b0;
    else if (done_i) hash_avliable <= 1'b1;
  end

  always_ff @(posedge clk_i or negedge resetn_i) begin
    if (!resetn_i) begin
      rdata_o <= 32'h0;
    end else if (rd_i) begin
      read_valid_o <= 1'b1;
      case (raddr_i)
        CFG_ADDR: rdata_o <= cfg_reg;
        CTL_ADDR: rdata_o <= ctl_reg;
        STS_ADDR: rdata_o <= sts_reg;
        IE_ADDR: rdata_o <= ie_reg;
        default:
          if (raddr_i[11:$clog2(`WORD_SIZE)] === HASH_ADDR[11:$clog2(`WORD_SIZE)]) begin
            for (int i = 0; i < HASH_SIZE/FIQSHA_BUS_DATA_WIDTH; i++) begin
              if (i === hash_reg_word_rptr)
                rdata_o = hash_reg[i*FIQSHA_BUS_DATA_WIDTH +: FIQSHA_BUS_DATA_WIDTH];
            end
          end
      endcase
    end else read_valid_o <= 1'b0;
  end
  typedef struct {
    logic [15:0] majorid;
    logic [15:0] minorid;
  } id_t;

  typedef struct {
    logic srst;
    logic hmacsavekey;
    logic hmacuseintkey;
    logic hmacauxkey;
    logic [3:0] opcode;
  } cfg_t;

  typedef struct {
    logic abort;
    logic last;
    logic init;
  } ctl_t;

  typedef struct {
    logic faultinjdet;
    logic busy;
    logic derr;
`ifndef HMACAUXKEY
    logic rdyk;
`endif
    logic rdyd;
    logic avl;
  } sts_t;

  typedef struct {
    logic faultinjdetie;
    logic busyie;
    logic derrie;
`ifndef HMACAUXKEY
    logic rdykie;
`endif
    logic rdydie;
    logic avlie;
  } ie_t;

  typedef struct {
    logic [255:0] hashhigh;
    logic [255:0] hash;
  } hash_t;

  typedef struct {
    logic [ARCH_SZ*8-1:0] statesh [3];
  } state_t;
  
  id_t id;
  cfg_t cfg;
  ctl_t ctl;
  sts_t sts;
  ie_t ie;

  always_comb begin
    id = '{majorid: id_reg[31:16],
           minorid: id_reg[15:0]};

    cfg = '{srst: cfg_reg[31],
           hmacsavekey: cfg_reg[6],
           hmacuseintkey: cfg_reg[5],
           hmacauxkey: cfg_reg[4],
           opcode: cfg_reg[3:0]};

    ctl = '{abort: ctl_reg[2],
           last: ctl_reg[1],
           init: ctl_reg[0]};

    sts = '{faultinjdet: sts_reg[5],
           busy: sts_reg[4],
           derr: sts_reg[3],
`ifndef HMACAUXKEY
           rdyk: sts_reg[2],
`endif
           rdyd: sts_reg[1],
           avl: sts_reg[0]};

    ie = '{faultinjdetie: ie_reg[5],
           busyie: ie_reg[4],
           derrie: ie_reg[3],
`ifndef HMACAUXKEY
           rdykie: ie_reg[2],
`endif
           rdydie: ie_reg[1],
           avlie: ie_reg[0]};
  end

  assign hash_reg = {hash_i[7],hash_i[6],hash_i[5],hash_i[4],
                     hash_i[3],hash_i[2],hash_i[1],hash_i[0]};
  assign sts_reg[5:4] = {fault_inj_det_i, !core_ready_i};
  assign sts_reg[1:0] = {ready_i, done_i || hash_avliable};
  assign sts_reg[31:5] = '0;
  assign start_o = ctl.init;
  assign last_o = ctl.last;
  assign abort_o = ctl.abort;
  assign opcode_o = cfg.opcode;
  assign data_o = din_reg;
  assign core_reset_o = !cfg.srst;
  assign dma_wr_req_o = sts.rdyd;
  assign dma_rd_req_o = sts.avl;
`ifndef HMACAUXKEY
  assign dma_wr_req_o = dma_wr_req_o || sts.rdyk;
  assign sts_reg[2] = key_ready_i;
`else
  assign sts_reg[2] = 1'b0;
`endif

`ifdef CORE_ARCH_S64
  assign s64 = cfg.opcode[2]||cfg.opcode[1];
`else `ifdef CORE_ARCH_S32
  assign s64 = 1'b1;
`endif `endif
  assign irq_o =
     (sts.faultinjdet & ie.faultinjdetie) |
     (sts.busy & ie.busyie) |
     (sts.derr & ie.derrie) |
`ifndef HMACAUXKEY
     (sts.rdyk & ie.rdykie) |
`endif
     (sts.rdyd & ie.rdydie) |
     (sts.avl & ie.avlie);

`ifdef HMACAUXKEY
logic [3:0] ctr = 0;
  always_ff @(posedge clk_i) begin
    key_valid_o <= key_ready_i;
    if (key_valid_o&&key_ready_i) begin
      if ((`KEY_SIZE-`WORD_SIZE/(s64?1:2)*ctr)<`WORD_SIZE/(s64?1:2)&&`KEY_SIZE-`WORD_SIZE/(s64?1:2)*ctr!=0) begin
        key_o <= '0;
        key_o[`WORD_SIZE-1-:`KEY_SIZE%`WORD_SIZE] <=
          aux_key_i[(`KEY_SIZE-1-`WORD_SIZE*ctr)-:((`KEY_SIZE%`WORD_SIZE))];
        ctr <= ctr + 1;
      end else if ((`KEY_SIZE-`WORD_SIZE/(s64?1:2)*ctr)>`KEY_SIZE || `KEY_SIZE-`WORD_SIZE/(s64?1:2)*ctr==0) begin
        key_o <= '0;
      end else begin
        ctr <= ctr + 1;
//        key_o <= '0;
        key_o <= ((`KEY_SIZE-`WORD_SIZE/(s64?1:2)*ctr)<`WORD_SIZE/(s64?1:2))?
        aux_key_i[(`KEY_SIZE-1-`WORD_SIZE*ctr)-:(`KEY_SIZE%(`WORD_SIZE))]:
        s64 ? aux_key_i[(`KEY_SIZE-1-`WORD_SIZE*ctr)-:`WORD_SIZE]:
              aux_key_i[(`KEY_SIZE-1-`WORD_SIZE/2*ctr)-:`WORD_SIZE/2];
      end
    end else if (start_o) begin
      ctr <= 1;
      key_o <= s64 ? aux_key_i[`KEY_SIZE-1-:`WORD_SIZE]:aux_key_i[`KEY_SIZE-1-:`WORD_SIZE/2];
    end
  end
`endif
endmodule
