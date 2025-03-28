//*
//*  Copyright (c) 2024 FortifyIQ, Inc.
//*
//*  All Rights Reserved.
//*
//*  All information contained herein is, and remains, the property of FortifyIQ, Inc.
//*  Dissemination of this information or reproduction of this material, in any medium,
//*  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
//*

`define FIQSHA_PRNG_INIT "SW"

module interface_control_logic #(
    parameter int FIQSHA_BUS_DATA_WIDTH = 32
  , parameter int FIQSHA_FIFO_SIZE = 4
  , parameter int BYTE_MAP_SZ = 2048
  , parameter int ARCH_SZ = 32
  , parameter bit INCLUDE_PRNG = 0
  , parameter bit BURST_EN = 0
  , parameter bit BYTE_ACCESS_EN = 0
  , parameter ID_VAL = 32'h0
) (
    input clk_i                                       // clock signal
  , input resetn_i                                    // reset,
  , input wr_i                                        // write from bus interface adapter
  , output reg wr_ack_o                               // write ackowledge to bus interface adapter
  , input rd_i                                        // read request from bus interface adapter
  , input rd_ack_i                                    // read ack from bus interface adapter
  , input [11:0] waddr_i                              // write address
  , input [11:0] wtransaction_cnt_i
  , input [11:0] raddr_i                              // read adress
  , input [11:0] rtransaction_cnt_i
  , input [FIQSHA_BUS_DATA_WIDTH-1:0] wdata_i         // write data
  , input [FIQSHA_BUS_DATA_WIDTH/8-1:0] wbyte_enable_i// write data bytes strobs
  , input [FIQSHA_BUS_DATA_WIDTH/8-1:0] rbyte_enable_i// read data bytes strobs
  , output reg [FIQSHA_BUS_DATA_WIDTH-1:0] rdata_o    // read data
  , output reg read_valid_o                           // read data validation strob
  , input read_ready_i                                // ready for read from a bus interface adapter
  , input [255:0] aux_key_i // dedicated key port to protected secret input instead bus transaction.
  , input wstuck_i
  , input rstuck_i
  , input [1:0] burst_type_i
  , input new_write_transaction_i
  , input wtransaction_active_i
  , input new_read_transaction_i
  , input rtransaction_active_i
  , output irq_o
  // native interface
  , output reg start_o
  , output abort_o
  , output last_o
  , output [3:0] opcode_o
  , output [ARCH_SZ*8-1:0] state_o
  , output [ARCH_SZ*8-1:0] state_share2_o
  , output [ARCH_SZ*8-1:0] state_share3_o
  , output [ARCH_SZ-1:0] data_o
  , input [ARCH_SZ*8-1:0] hash_i
  , output reg valid_o
  , input ready_i
  , input core_ready_i
  , input done_i
  , input fault_inj_det_i
  , output dma_wr_req_o
  , output dma_rd_req_o
  , output slv_error_o
  , output reg core_reset_o
);

  typedef struct {
    logic [15:0] majorid;
    logic [15:0] minorid;
  } id_t;

  typedef struct {
    logic srst;
    logic [4:0] fifointhld;
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
    logic [4:0] fifoinlvl;
    logic keyunlocked;
    logic faultinjdet;
    logic busy;
    logic derr;
    logic rdy;
    logic avl;
  } sts_t;

  typedef struct {
    logic keyunlockedie;
    logic faultinjdetie;
    logic busyie;
    logic derrie;
    logic rdyie;
    logic avlie;
  } ie_t;

  typedef struct {
    logic [255:0] hashhigh;
    logic [255:0] hash;
  } hash_t;

  typedef struct {
    logic [ARCH_SZ*8-1:0] statesh [3];
  } state_t;

  typedef struct {
    logic [(`FIQSHA_PRNG_INIT == "SW" ? 31 : 0) : 0] seed;
  } seed_t;

  logic [31:0] id_reg = ID_VAL;
  logic [31:0] cfg_reg, ctl_reg, sts_reg, ie_reg, seed_reg;
  logic [8*ARCH_SZ-1:0] hash_reg;
  logic [8*3*ARCH_SZ-1:0] state_reg;
  logic fifo_fixed_transaction;
  logic block_fixed_wtransaction_incr;
  logic block_fixed_rtransaction_incr;
  logic wr_less_than_bus_width;
  logic rd_less_than_bus_width;
  
  logic init_ack, last_ack, abort_ack, avl_clr, rdy_clr,
          derr_clr, busy_clr, faultinjdet_clr, keyunlocked_clr,
            avl_set, rdy_set, derr_set, busy_set,
              faultinjdet_set, keyunlocked_set;

  localparam byte BUS_DATA_IN_ARCH_SZ = (ARCH_SZ + FIQSHA_BUS_DATA_WIDTH - 1)/FIQSHA_BUS_DATA_WIDTH;
  localparam FIFO_DATA_WIDTH = ARCH_SZ >= FIQSHA_BUS_DATA_WIDTH ? FIQSHA_BUS_DATA_WIDTH : ARCH_SZ;
  logic [FIFO_DATA_WIDTH-1:0] fifo [FIQSHA_FIFO_SIZE][BUS_DATA_IN_ARCH_SZ];

  localparam shortint FIFO_WADDR_SZ =
    $clog2(FIQSHA_FIFO_SIZE) +
    $clog2((ARCH_SZ + FIQSHA_BUS_DATA_WIDTH - 1)/FIQSHA_BUS_DATA_WIDTH);

  logic [FIFO_WADDR_SZ:0] fifo_wr_ptr, fifo_wr_ptr_comb;
  logic fifo_rd;
  logic [$clog2(FIQSHA_FIFO_SIZE):0] fifo_rd_ptr, fifo_rd_ptr_comb;
  logic [$clog2(FIQSHA_FIFO_SIZE):0] fifo_deposit, fifo_deposit_comb;
  logic empty, overflow, upborder;
  logic empty_comb, overflow_comb, upborder_comb;

  localparam ID_ADDR = 12'h0;
  localparam CFG_ADDR = 12'h10;
  localparam CTL_ADDR = 12'h20;
  localparam STS_ADDR = 12'h30;
  localparam IE_ADDR = 12'h40;
  localparam SEED_ADDR = 12'h300;

  localparam DIN_START_ADDR = 12'h140;
  localparam DIN_SIZE = ARCH_SZ == 32 ? (4 * 32) : (4 * 64);
  localparam HASH_ADDR = 12'h100;
  localparam HASH_SIZE = ARCH_SZ == 32 ? (8 * 32) : (8 * 64);
  localparam STATE_ADDR = 12'h200;
  localparam STATE_SIZE = 3*HASH_SIZE;

  wire use_extended_waddr =
       BURST_EN
    && burst_type_i == 2'b00
    && !fifo_fixed_transaction
    && !block_fixed_wtransaction_incr;

  wire use_extended_raddr =
       BURST_EN
    && burst_type_i == 2'b00
    && !block_fixed_rtransaction_incr;

  wire [11:0] waddr_actual = use_extended_waddr ?
    waddr_i + (wtransaction_cnt_i << $clog2(FIQSHA_BUS_DATA_WIDTH/8)) :
    waddr_i;

  wire [11:0] raddr_actual = use_extended_raddr ?
    raddr_i + (rtransaction_cnt_i << $clog2(FIQSHA_BUS_DATA_WIDTH/8)) :
    raddr_i;
  
  wire [$clog2(STATE_SIZE/8)-$clog2(FIQSHA_BUS_DATA_WIDTH/8)-1:0] state_reg_word_wptr = 
    waddr_actual[$clog2(STATE_SIZE/8)-1:$clog2(FIQSHA_BUS_DATA_WIDTH/8)];

  wire state_reg_write_access = waddr_actual[11:$clog2(STATE_SIZE/8)] === STATE_ADDR[11:$clog2(STATE_SIZE/8)];

  always_ff @(posedge clk_i or negedge resetn_i) begin
    if (~resetn_i) begin
      cfg_reg <= '0;
      ctl_reg <= '0;
      sts_reg <= 32'h2;
      ie_reg <= 32'h2;
      seed_reg <= '0;
    end else begin
      sts_reg[12:8] <= fifo_deposit_comb;
      if (avl_set)
        sts_reg[0] <= 1'b1;
      else if (avl_clr)
        sts_reg[0] <= 1'b0;
      if (rdy_set)
        sts_reg[1] <= 1'b1;
      else if (rdy_clr)
        sts_reg[1] <= 1'b0;
      if (derr_set)
        sts_reg[2] <= 1'b1;
      else if (derr_clr)
        sts_reg[2] <= 1'b0;
      if (busy_set)
        sts_reg[3] <= 1'b1;
      else if (busy_clr)
        sts_reg[3] <= 1'b0;
      if (faultinjdet_set)
        sts_reg[4] <= 1'b1;
      else if (faultinjdet_clr)
        sts_reg[4] <= 1'b0;
      if (keyunlocked_set)
        sts_reg[5] <= 1'b1;
      else if (keyunlocked_clr)
        sts_reg[5] <= 1'b0;
      if (wr_i) begin
        case (waddr_actual[11:2])
          CFG_ADDR[11:2]: begin
            cfg_reg <= {wdata_i[31], 18'h0, wdata_i[12:8], 1'b0, wdata_i[6:0]};
          end
          CTL_ADDR[11:2]: begin
            ctl_reg[31:1] <= {29'h0, wdata_i[2:1]};
            if (wdata_i[0])
              ctl_reg[0] <= 1'b1;
          end
          STS_ADDR[11:2]: begin
            if (wdata_i[5])
              sts_reg[5] <= 1'b0;
            if (wdata_i[2])
              sts_reg[2] <= 1'b0;
          end
          IE_ADDR[11:2]: begin
            ie_reg <= {27'h0, wdata_i[5:0]};
          end
          SEED_ADDR[11:2]: begin
            if (`FIQSHA_PRNG_INIT == "SW")
              seed_reg <= wdata_i[31:0];
            else
              seed_reg <= {31'h0, wdata_i[0]};
          end
          default: begin
            if (state_reg_write_access) begin
              for (int i = 0; i < STATE_SIZE/FIQSHA_BUS_DATA_WIDTH; i++) begin
                if (i === state_reg_word_wptr)
                  state_reg[i*FIQSHA_BUS_DATA_WIDTH +: FIQSHA_BUS_DATA_WIDTH] <= wdata_i;
              end
            end
          end
        endcase // waddr_i[11:2]
      end
      if (abort_ack)
        ctl_reg[2] <= 1'b0;
      if (last_ack)
        ctl_reg[1] <= 1'b0;
      if (init_ack)
        ctl_reg[0] <= 1'b0;
      if (cfg.srst) begin
        cfg_reg <= '0;
        ctl_reg <= '0;
        sts_reg <= 32'h2;
        ie_reg <= 32'h2;
        state_reg <= '0;
      end
    end
  end

  wire fifo_waccess = waddr_actual[11:$clog2(DIN_SIZE/8)] === DIN_START_ADDR[11:$clog2(DIN_SIZE/8)];

  if (BURST_EN) begin

    always_comb begin
      wr_less_than_bus_width = 0;
      if (wr_i) begin
        case (waddr_actual[11:2])
          CFG_ADDR[11:2]: begin
            wr_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32;
          end
          CTL_ADDR[11:2]: begin
            wr_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32;
          end
          STS_ADDR[11:2]: begin
            wr_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32;
          end
          IE_ADDR[11:2]: begin
            wr_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32;
          end
          SEED_ADDR[11:2]: begin
            wr_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32;
          end
          default: begin
            if (waddr_actual[11:$clog2(STATE_SIZE/8)] === STATE_ADDR[11:$clog2(STATE_SIZE/8)]) begin
              wr_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > STATE_SIZE;
            end
          end
        endcase // waddr_i[11:2]
      end
    end

    always_comb begin
      rd_less_than_bus_width = '0;
      case (raddr_actual[11:2])
        ID_ADDR[11:2]: begin
          rd_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32 && rd_i;
        end
        CFG_ADDR[11:2]: begin
          rd_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32 && rd_i;
        end
        CTL_ADDR[11:2]: begin
          rd_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32 && rd_i;
        end
        STS_ADDR[11:2]: begin
          rd_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32 && rd_i;
        end
        IE_ADDR[11:2]: begin
          rd_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32 && rd_i;
        end
        SEED_ADDR[11:2]: begin
          rd_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > 32 && rd_i;
        end
        default: begin
          if (raddr_actual[11:$clog2(STATE_SIZE/8)] === STATE_ADDR[11:$clog2(STATE_SIZE/8)]) begin
            rd_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > STATE_SIZE && rd_i;
          end else if (raddr_actual[11:$clog2(HASH_SIZE/8)] === HASH_ADDR[11:$clog2(HASH_SIZE/8)]) begin
            rd_less_than_bus_width = BURST_EN && FIQSHA_BUS_DATA_WIDTH > HASH_SIZE && rd_i;
          end
        end
      endcase
    end

    always_ff @(posedge clk_i or negedge resetn_i) begin
      if (~resetn_i) begin
        fifo_fixed_transaction <= 1'b0;
      end else begin
        if (~wtransaction_active_i) begin
          fifo_fixed_transaction <= 1'b0;
        end else if (new_write_transaction_i && fifo_waccess && burst_type_i == 2'b00) begin
          fifo_fixed_transaction <= 1'b1;
        end
      end
    end

    always_ff @(posedge clk_i or negedge resetn_i) begin
      if (~resetn_i) begin
        block_fixed_wtransaction_incr <= 1'b0;
      end else begin
        if (~wtransaction_active_i) begin
          block_fixed_wtransaction_incr <= 1'b0;
        end else if (new_write_transaction_i && wr_less_than_bus_width && burst_type_i == 2'b00) begin
          block_fixed_wtransaction_incr <= 1'b1;
        end
      end
    end

    always_ff @(posedge clk_i or negedge resetn_i) begin
      if (~resetn_i) begin
        block_fixed_rtransaction_incr <= 1'b0;
      end else begin
        if (~rtransaction_active_i) begin
          block_fixed_rtransaction_incr <= 1'b0;
        end else if (new_read_transaction_i && rd_less_than_bus_width && burst_type_i == 2'b00) begin
          block_fixed_rtransaction_incr <= 1'b1;
        end
      end
    end
  end

  logic [FIFO_WADDR_SZ-1:0] incrval;

  always_comb begin
    fifo_wr_ptr_comb = fifo_wr_ptr;
    fifo_rd_ptr_comb = fifo_rd_ptr;
    fifo_deposit_comb = fifo_deposit;
    if (wr_i && fifo_waccess && !overflow) begin
      // if (FIQSHA_BUS_DATA_WIDTH <= ARCH_SZ) begin
        fifo_wr_ptr_comb = fifo_wr_ptr + 1;
      // end else begin
      //   fifo_wr_ptr_comb = fifo_wr_ptr + FIQSHA_BUS_DATA_WIDTH/ARCH_SZ;
      // end
    end
    if (fifo_rd && !empty) begin
      fifo_rd_ptr_comb = fifo_rd_ptr + 1;
    end
    if (cfg.srst || ctl.abort) begin
      fifo_wr_ptr_comb = '0;
      fifo_rd_ptr_comb = '0;
      fifo_deposit_comb = '0;
    end
    fifo_deposit_comb = fifo_wr_ptr_comb[FIFO_WADDR_SZ -: $clog2(FIQSHA_FIFO_SIZE)+1] -
                          fifo_rd_ptr_comb;
    overflow_comb = fifo_deposit_comb >= FIQSHA_FIFO_SIZE;
    empty_comb = fifo_deposit_comb == 0;
    upborder_comb = fifo_deposit_comb >= cfg.fifointhld;
  end

  assign fifo_rd = valid_o & ready_i & ~empty;

  always_ff @(posedge clk_i or negedge resetn_i) begin
    if (~resetn_i) begin
      fifo_wr_ptr <= '0;
      fifo_rd_ptr <= '0;
      fifo_deposit <= '0;
      empty <= 1'b1;
      overflow <= 1'b0;
      upborder <= 1'b0;
    end else begin
      fifo_wr_ptr <= fifo_wr_ptr_comb;
      fifo_rd_ptr <= fifo_rd_ptr_comb;
      fifo_deposit <= fifo_deposit_comb;
      empty <= empty_comb;
      overflow <= overflow_comb;
      upborder <= upborder_comb;
    end
  end

  always_ff @(posedge clk_i) begin
    if (wr_i && fifo_waccess && !overflow) begin
      if (FIQSHA_BUS_DATA_WIDTH <= ARCH_SZ) begin
        fifo
          [fifo_wr_ptr[$clog2(BUS_DATA_IN_ARCH_SZ) +: $clog2(FIQSHA_FIFO_SIZE)]]
          [BUS_DATA_IN_ARCH_SZ == 1 ? 0 :
            waddr_i[
              $clog2(FIQSHA_BUS_DATA_WIDTH/8) +:
              BUS_DATA_IN_ARCH_SZ == 1 ? 1 : $clog2(BUS_DATA_IN_ARCH_SZ)
            ]
          ]
            // fifo_wr_ptr[0 +: BUS_DATA_IN_ARCH_SZ == 1 ? 1 : $clog2(BUS_DATA_IN_ARCH_SZ)]]
          <= wdata_i;
      end else begin
        fifo[fifo_wr_ptr[FIFO_WADDR_SZ-1 : 0]][0] <= '0;
        fifo[fifo_wr_ptr[FIFO_WADDR_SZ-1 : 0]][0] <= wdata_i[0+:ARCH_SZ];
      end
    end
  end

  logic core_reset_delay;

  assign abort_ack = ctl.abort;
  assign last_ack = last_o;
  assign init_ack = ctl.init & start_o;
  assign derr_set = wr_i & fifo_waccess & overflow;
  assign busy_set = ~core_ready_i && core_reset_delay;
  assign busy_clr = core_ready_i;
  assign rdy_set = empty;
  assign rdy_clr = (upborder | overflow) & ~empty;
  assign avl_set = done_i;
  assign avl_clr = rd_i & raddr_i == HASH_ADDR;
  assign derr_clr = rd_i & raddr_i == STS_ADDR;
  assign faultinjdet_clr = rd_i & raddr_i == STS_ADDR;
  assign keyunlocked_clr = cfg.hmacsavekey;
  assign faultinjdet_set = fault_inj_det_i;
  assign keyunlocked_set = done_i;

  id_t id;
  cfg_t cfg;
  ctl_t ctl;
  sts_t sts;
  ie_t ie;
  hash_t hash;
  state_t state;
  seed_t seed;

  always_comb begin
    id = '{
        majorid: id_reg[31:16]
      , minorid: id_reg[15:0]
    };

    cfg = '{
        srst: cfg_reg[31]
      , fifointhld: cfg_reg[12:8]
      , hmacsavekey: cfg_reg[6]
      , hmacuseintkey: cfg_reg[5]
      , hmacauxkey: cfg_reg[4]
      , opcode: cfg_reg[3:0]
    };

    ctl = '{
        abort: ctl_reg[2]
      , last: ctl_reg[1]
      , init: ctl_reg[0]
    };

    sts = '{
        fifoinlvl: sts_reg[12:8]
      , keyunlocked: sts_reg[5]
      , faultinjdet: sts_reg[4]
      , busy: sts_reg[3]
      , derr: sts_reg[2]
      , rdy: sts_reg[1]
      , avl: sts_reg[0]
    };

    ie = '{
        keyunlockedie: ie_reg[5]
      , faultinjdetie: ie_reg[4]
      , busyie: ie_reg[3]
      , derrie: ie_reg[2]
      , rdyie: ie_reg[1]
      , avlie: ie_reg[0]
    };

    if (ARCH_SZ > 32)
      hash.hashhigh = hash_reg[4*ARCH_SZ +: 4*ARCH_SZ];
    else
      hash.hash[4*ARCH_SZ +: 4*ARCH_SZ] = hash_reg[4*ARCH_SZ +: 4*ARCH_SZ];
    hash.hash[0 +: 4*ARCH_SZ] = hash_reg[0 +: 4*ARCH_SZ];

    for (int j = 0; j < 3; j++) begin
      state.statesh[j] = state_reg[j*8*ARCH_SZ +: 8*ARCH_SZ];
    end

    if (`FIQSHA_PRNG_INIT == "SW") begin
      seed.seed = seed_reg;
    end else begin
      seed.seed = seed_reg[0];
    end
  end

  assign irq_o =
      (sts.keyunlocked & ie.keyunlockedie)
    | (sts.faultinjdet & ie.faultinjdetie)
    | (sts.busy & ie.busyie)
    | (sts.derr & ie.derrie)
    | (sts.rdy & ie.rdyie)
    | (sts.avl & ie.avlie);

  always_ff @(posedge clk_i) begin
    if (done_i)
      hash_reg <= hash_i;
    if (cfg.srst)
      hash_reg <= '0;
  end

  always_ff @(posedge clk_i or negedge resetn_i) begin
    if (~resetn_i) begin
      wr_ack_o <= 1'b0;
    end else begin
      wr_ack_o <= wr_i & ~(fifo_waccess & overflow);
    end
  end

  assign state_o = cfg.hmacsavekey ? aux_key_i : state.statesh[0];
  assign state_share2_o = cfg.hmacsavekey ? '0 : state.statesh[1];
  assign state_share3_o = cfg.hmacsavekey ? '0 : state.statesh[2];

  assign dma_wr_req_o = sts.rdy;
  assign dma_rd_req_o = sts.avl;
  assign slv_error_o = sts.derr;


  logic [3:0] data_cnt;
  assign abort_o = ctl.abort;
  assign last_o = ctl.last;
  assign opcode_o = cfg.opcode;

  if (ARCH_SZ > FIQSHA_BUS_DATA_WIDTH) begin
    wire [ARCH_SZ-1:0] data_o_restored_word_order;
    for (genvar c = 0; c < BUS_DATA_IN_ARCH_SZ; c++) begin: l_gen_data_o
      assign data_o_restored_word_order[c*FIQSHA_BUS_DATA_WIDTH+:FIQSHA_BUS_DATA_WIDTH] =
        fifo[fifo_rd_ptr[0+:$clog2(FIQSHA_FIFO_SIZE)]][BUS_DATA_IN_ARCH_SZ-1-c];
    end
    assign data_o =
      cfg.opcode[2:1] === 2'b00 ? data_o_restored_word_order >> 32 : data_o_restored_word_order;
  end else begin
    assign data_o =
      fifo[fifo_rd_ptr[0+:$clog2(FIQSHA_FIFO_SIZE)]][0][0 +: ARCH_SZ];
  end

  always_ff @(posedge clk_i or negedge resetn_i) begin
    if (~resetn_i) begin
      start_o <= 1'b0;
      valid_o <= 1'b0;
      data_cnt <= '0;
    end else begin
      if (cfg.srst) begin
        start_o <= 1'b0;
        valid_o <= 1'b0;
        data_cnt <= '0;
      end else begin
        if (start_o & ready_i & valid_o) begin
          start_o <= 1'b0;
        end else if (core_ready_i & ctl.init & ~empty) begin
          start_o <= 1'b1;
          data_cnt <= '0;
        end
        if (ready_i & valid_o & empty_comb) begin
          valid_o <= 1'b0;
        end else if ((~empty & ~core_ready_i) | (core_ready_i & ctl.init & ~empty)) begin
          valid_o <= 1'b1;
        end
        if (ready_i & valid_o) begin
          data_cnt <= data_cnt + 1;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge resetn_i) begin // CHECK THIS IN THE CODE REVIEW!!!!!!!!!!!!!
    if (!resetn_i) begin
      core_reset_o <= 1'b0;
      core_reset_delay <= 1'b0;
    end else begin
      core_reset_o <= ~cfg.srst;
      core_reset_delay <= core_reset_o;
    end
  end

  wire [$clog2(STATE_SIZE/8)-$clog2(FIQSHA_BUS_DATA_WIDTH/8)-1:0] state_reg_word_rptr = 
    raddr_actual[$clog2(STATE_SIZE/8)-1:$clog2(FIQSHA_BUS_DATA_WIDTH/8)];
  wire [$clog2(HASH_SIZE/8)-$clog2(FIQSHA_BUS_DATA_WIDTH/8)-1:0] hash_reg_word_rptr = 
    raddr_actual[$clog2(HASH_SIZE/8)-1:$clog2(FIQSHA_BUS_DATA_WIDTH/8)];
          
  // TODO
  always_comb begin
    rdata_o = '0;
    case (raddr_actual[11:2])
      ID_ADDR[11:2]: begin
        rdata_o[31:16] = id.majorid;
        rdata_o[15:0] = id.minorid;
      end
      CFG_ADDR[11:2]: begin
        rdata_o[3:0] = cfg.opcode;
        rdata_o[4] = cfg.hmacauxkey;
        rdata_o[5] = cfg.hmacuseintkey;
        rdata_o[6] = cfg.hmacsavekey;
        rdata_o[12:8] = cfg.fifointhld;
      end
      CTL_ADDR[11:2]: begin
        rdata_o[0] = ctl.init;
        rdata_o[1] = ctl.last;
        rdata_o[2] = ctl.abort;
      end
      STS_ADDR[11:2]: begin
        rdata_o[0] = sts.avl;
        rdata_o[1] = sts.rdy;
        rdata_o[2] = sts.derr;
        rdata_o[3] = sts.busy;
        rdata_o[4] = sts.faultinjdet;
        rdata_o[5] = sts.keyunlocked;
        rdata_o[12:8] = sts.fifoinlvl;
      end
      IE_ADDR[11:2]: begin
        rdata_o[0] = ie.avlie;
        rdata_o[1] = ie.rdyie;
        rdata_o[2] = ie.derrie;
        rdata_o[3] = ie.busyie;
        rdata_o[4] = ie.faultinjdetie;
        rdata_o[5] = ie.keyunlockedie;
      end
      SEED_ADDR[11:2]: begin
        if (`FIQSHA_PRNG_INIT == "SW")
          rdata_o[31:0] = seed.seed;
        else
          rdata_o[0] = seed.seed;
      end
      default: begin
        if (raddr_actual[11:$clog2(STATE_SIZE/8)] === STATE_ADDR[11:$clog2(STATE_SIZE/8)]) begin
          for (int i = 0; i < STATE_SIZE/FIQSHA_BUS_DATA_WIDTH; i++) begin
            if (i === state_reg_word_rptr)
              rdata_o = state_reg[i*FIQSHA_BUS_DATA_WIDTH +: FIQSHA_BUS_DATA_WIDTH];
          end
        end else if (raddr_actual[11:$clog2(HASH_SIZE/8)] === HASH_ADDR[11:$clog2(HASH_SIZE/8)]) begin
          for (int i = 0; i < HASH_SIZE/FIQSHA_BUS_DATA_WIDTH; i++) begin
            if (i === hash_reg_word_rptr)
              rdata_o = hash_reg[i*FIQSHA_BUS_DATA_WIDTH +: FIQSHA_BUS_DATA_WIDTH];
          end
        end
      end
    endcase
    read_valid_o = rd_i;
  end

endmodule