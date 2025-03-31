`ifndef IF_DEF
`define IF_DEF
`define ARCH_SZ `WORD_SIZE

interface native_if_t (input logic clk);
  logic start;
  logic abort;
  logic last;
  logic [3:0] opcode;
  logic [`ARCH_SZ-1:0] data;
  logic [`ARCH_SZ*8-1:0] hash;
  logic valid;
  logic ready;
  logic core_ready;
  logic done;
  logic fault_inj_det;

  task automatic read_data (input int num, ref logic [`ARCH_SZ-1:0] q_data [$]);
    begin
      int t = $urandom_range(1,3);
      int cnt = 0;
      do begin
        @(posedge clk);
        if (valid & ready) begin
          ready = 0;
          cnt++;
          q_data.push_back(data);
          t = $urandom_range(1,10);
        end else if (valid) begin
          t--;
          if (t == 0)
            ready = 1;
        end
      end while (cnt < num && fault_inj_det == 0);
      @(posedge clk);
    end
  endtask : read_data

  task automatic send_hash;
    begin
      int t = $urandom_range(10,30);
      repeat (t) @(posedge clk);
      core_ready = 1;
      done = 1;
      for (int i = 0; i < 8*`ARCH_SZ/32; i++)
        hash[i*32+:32] = $random();
      @(posedge clk);
      done = 0;
    end
  endtask : send_hash

  task automatic init ();
    begin
      hash = '0;
      ready = '0;
      core_ready = '1;
      done = '0;
      fault_inj_det = '0;
    end
  endtask : init

  modport mst (
      input clk
    , output start
    , output abort
    , output last
    , output opcode
    , output data
    , input hash
    , output valid
    , input ready
    , input core_ready
    , input done
    , input fault_inj_det
  );

  modport slv (
      input clk
    , input start
    , input abort
    , input last
    , input opcode
    , input data
    , output hash
    , input valid
    , output ready
    , output core_ready
    , output done
    , output fault_inj_det
    , import read_data
    , import send_hash
    , import init
  );
endinterface : native_if_t

interface slave_adapter_if_t #(parameter BUS_DATA_WIDTH = 32) (input clk);
  logic resetn;
  logic wr;
  logic wr_ack;
  logic rd;
  logic rd_ack;
  logic [11:0] waddr;
  logic [11:0] wtransaction_cnt;
  logic [11:0] raddr;
  logic [11:0] rtransaction_cnt;
  logic [BUS_DATA_WIDTH-1:0] wdata;
  logic [BUS_DATA_WIDTH/8-1:0] wbyte_enable;
  logic [BUS_DATA_WIDTH/8-1:0] rbyte_enable;
  logic [BUS_DATA_WIDTH-1:0] rdata;
  logic read_valid;
  logic read_ready;
  logic wstuck;
  logic rstuck;
  logic [1:0] burst_type;
  logic new_write_transaction;
  logic wtransaction_active;
  logic new_read_transaction;
  logic rtransaction_active;

  task automatic init ();
    begin
      wr = '0;
      rd = '0;
      rd_ack = '0;
      waddr = '0;
      wtransaction_cnt = '0;
      raddr = '0;
      rtransaction_cnt = '0;
      wdata = '0;
      wbyte_enable = '0;
      rbyte_enable = '0;
      read_ready = '0;
      wstuck = '0;
      rstuck = '0;
      burst_type = '0;
      new_write_transaction = '0;
      wtransaction_active = '0;
      new_read_transaction = '0;
      rtransaction_active = '0;
    end
  endtask: init

  task automatic write (
      input int num
    , input logic burst_enable
    , input logic [1:0] burst_type
    , input logic [11:0] addr
    , ref logic [BUS_DATA_WIDTH-1:0] q_data [$]
  );
    begin
      int cnt = 0;
      wr = 0;
      wtransaction_cnt = 0;
      wtransaction_active = 0;
      @(posedge clk);
      waddr = addr;
      do begin
        wr = 1'b1;
        wdata = q_data.pop_front();
        new_write_transaction = cnt == 0;
        wtransaction_active = 1'b1;
        @(posedge clk);
        cnt++;
        if (burst_enable && cnt < num) begin
          if (burst_type == 2'b00)
            wtransaction_cnt++;
          else
            waddr += (1 << $clog2(BUS_DATA_WIDTH/8));
        end else if (!burst_enable) begin
          waddr += (1 << $clog2(BUS_DATA_WIDTH/8));
          wr = 0;
          @(posedge clk);
        end
      end while (cnt < num);
      wr = 0;
      wtransaction_active = 1'b0;
    end
  endtask: write

  task automatic read (
      input int num
    , input logic burst_enable
    , input logic [1:0] burst_type
    , input logic [11:0] addr
    , ref logic [BUS_DATA_WIDTH-1:0] q_data [$]
  );
    begin
      int cnt = 0;
      rd = 0;
      rd_ack = 0;
      rtransaction_cnt = 0;
      rtransaction_active = 0;
      @(posedge clk);
      raddr = addr;
      do begin
        rd = 1'b1;
        new_read_transaction = cnt == 0;
        rtransaction_active = 1'b1;
        @(negedge clk);
        q_data.push_back(rdata);
        @(posedge clk);
        rd_ack = 1;
        cnt++;
        if (burst_enable && cnt < num) begin
          if (burst_type == 2'b00)
            rtransaction_cnt++;
          else
            raddr += (1 << $clog2(BUS_DATA_WIDTH/8));
        end else if (!burst_enable) begin
          raddr += (1 << $clog2(BUS_DATA_WIDTH/8));
          rd = 0;
          @(posedge clk);
          rd_ack = 0;
        end
      end while (cnt < num);
      rd = 0;
      rtransaction_active = 1'b0;
      @(posedge clk);
      rd_ack = 0;
    end
  endtask: read

  modport mst (
      input clk
    , input resetn
    , output wr
    , input wr_ack
    , output rd
    , output rd_ack
    , output waddr
    , output wtransaction_cnt
    , output raddr
    , output rtransaction_cnt
    , output wdata
    , output wbyte_enable
    , output rbyte_enable
    , input rdata
    , input read_valid
    , output read_ready
    , output wstuck
    , output rstuck
    , output burst_type
    , output new_write_transaction
    , output wtransaction_active
    , output new_read_transaction
    , output rtransaction_active
    , import init
    , import write
    , import read
  );

  modport slv (
      input clk
    , input resetn
    , input wr
    , output wr_ack
    , input rd
    , input rd_ack
    , input waddr
    , input wtransaction_cnt
    , input raddr
    , input rtransaction_cnt
    , input wdata
    , input wbyte_enable
    , input rbyte_enable
    , output rdata
    , output read_valid
    , input read_ready
    , input wstuck
    , input rstuck
    , input burst_type
    , input new_write_transaction
    , input wtransaction_active
    , input new_read_transaction
    , input rtransaction_active
  );


endinterface : slave_adapter_if_t


`endif