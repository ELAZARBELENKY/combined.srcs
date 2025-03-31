`include "interfaces.sv"

`ifndef ENV_DEF
`define ENV_DEF


`include "apb_if.sv"
`include "base_types.sv"

`define N_TEST 10

class environment #(parameter BUS_DATA_WIDTH = 32, parameter ARCH_SZ = `WORD_SIZE);

  virtual native_if_t.slv native_if;
  virtual slave_adapter_if_t.mst slv_bus_if;
  virtual apb_if.mst apb;


  typedef enum {
    IDLE, READ_ALL, WRITE_CFG, SEND_START, SEND_ABORT,
    SEND_LAST, WRITE_DATA, READ_STS, READ_HASH, WRITE_ALL} fsm_t;

  fsm_t fsm;
  int testcnt;

  test_cfg_t test_sets [$];
  test_cfg_t test_set;

  logic [BUS_DATA_WIDTH-1:0] q_wdata [$];
  logic [BUS_DATA_WIDTH-1:0] q_rdata [$];
  logic [`ARCH_SZ-1:0] q_rdata_native [$];

  function new (
      virtual native_if_t.slv native_if
    , virtual slave_adapter_if_t.mst slv_bus_if
    , virtual apb_if.mst apb
  );
    begin
      this.fsm = IDLE;
      this.testcnt = 0;
      this.native_if = native_if;
      this.slv_bus_if = slv_bus_if;
      this.apb = apb;
    end
  endfunction : new

  task init_test;
    $timeformat(-12, 0, "ps", 0);
    slv_bus_if.init();
    native_if.init();
    apb.init();
    // NIST test 1
    test_set.id = 0;
    test_set.hmac = 1'b0;
    test_set.msg.delete();
    test_set.msg.push_back('{
      'h6162638000000000, 'h0000000000000000, 'h0000000000000000, 'h0000000000000000,
      'h0000000000000000, 'h0000000000000000, 'h0000000000000000, 'h0000000000000000,
      'h0000000000000000, 'h0000000000000000, 'h0000000000000000, 'h0000000000000000,
      'h0000000000000000, 'h0000000000000000, 'h0000000000000000, 'h0000000000000018
    });

    test_set.hash = '{
      'h2A9AC94FA54CA49F, 'h454D4423643CE80E, 'h36BA3C23A3FEEBBD, 'h2192992A274FC1A8,
      'h0A9EEEE64B55D39A, 'h12E6FA4E89A97EA2, 'hCC417349AE204131, 'hDDAF35A193617ABA
    };
    test_sets.push_back(test_set);
  endtask

  int data_cnt = 0;
  logic [ARCH_SZ-1:0] data;
  logic [31:0] regdata;

  logic [7:0] bus_data_bytes [$];
  logic [ARCH_SZ-1:0] hash [8];
  logic error;
  int cnt;

  int wrcnt;

  task run_apb ();
    begin
      do begin
        test_set = test_sets.pop_front();
         $display("MESSAGE:");
         for (int i = 0; i < test_set.msg.size(); i++) begin
           for (int j = 0; j < 16; j++) begin
             $display("msg[%0d][%0d] = %0x",i,j,test_set.msg[i][j]);
           end
         end
        bus_data_bytes.delete();
//        for (int i = 0; i < 3; i++) begin
//          for (int j = 0; j < 8; j++) begin
//            for (int k = 0; k < ARCH_SZ/8; k++) begin
//              bus_data_bytes.push_back(test_set.init_state_shares[i][j][k*8+:8]);
//            end
//          end
//        end
        apb.write(
          .delay(0), .id(0), .address(12'h020), .length(ARCH_SZ/BUS_DATA_WIDTH*8*3),
          .size(0), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
        );
        regdata = {19'h0, 5'h4, 1'b0, 1'b0, 1'b0, 1'b0, test_set.hmac, 3'b010};
        bus_data_bytes.delete();
        for (int k = 0; k < 32/8; k++) begin
          bus_data_bytes.push_back(regdata[k*8+:8]);
        end
         if (BUS_DATA_WIDTH > 32) begin
           for (int k = 0; k < (BUS_DATA_WIDTH-32)/8; k++) begin
             bus_data_bytes.push_back('0);
           end
         end
        apb.write(
          .delay(0), .id(0), .address(12'h010), .length(1),
          .size(0), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
        );
        bus_data_bytes.delete();
        for (int k = 0; k < BUS_DATA_WIDTH/8; k++) begin
          bus_data_bytes.push_back('1);
        end
        apb.write(
          .delay(0), .id(0), .address(12'h040), .length(1),
          .size(0), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
        );
        bus_data_bytes.delete();
        do begin
          apb.read(
            .delay(0), .id(0), .address(12'h030), .length(1),
            .size(2), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
          );
          for (int i = 0; i < 4; i++) begin
            regdata[i*8+:8] = bus_data_bytes.pop_front();
          end
        end while (!regdata[1] || regdata[12:8] > 0);
        bus_data_bytes.delete();
        for (int i = 0; i < test_set.msg.size(); i++) begin
          // write 1st quad
          wrcnt = 0;
          for (int j = 0; j < 4; j++) begin
            bus_data_bytes.delete();
            for (int k = 0; k < 4; k++) begin
              for (int l = 0; l < ARCH_SZ/8; l++) begin
                bus_data_bytes.push_back(test_set.msg[i][j*4+k][8*l+:8]);
              end
            end
            apb.write(
              .delay(0), .id(0), .address(12'h140), .length(4*ARCH_SZ/BUS_DATA_WIDTH),
              .size(0), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
            );
          end
          if (i == 0) begin
            regdata = 32'h1;
            bus_data_bytes.delete();
            for (int k = 0; k < 32/8; k++) begin
              bus_data_bytes.push_back(regdata[k*8+:8]);
            end
            if (BUS_DATA_WIDTH > 32) begin
              for (int k = 0; k < (BUS_DATA_WIDTH-32)/8; k++) begin
                bus_data_bytes.push_back('0);
              end
            end
            apb.write(
              .delay(0), .id(0), .address(12'h020), .length(1),
              .size(0), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
            );
          end
          if ( i != test_set.msg.size() - 1 && test_set.msg.size() > 1) begin
            bus_data_bytes.delete();
            do begin
              apb.read(
                .delay(0), .id(0), .address(12'h030), .length(1),
                .size(2), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
              );
              for (int i = 0; i < 4; i++) begin
                regdata[i*8+:8] = bus_data_bytes.pop_front();
              end
            end while (regdata[12:8] > 0);
          end
        end
        regdata = 32'h2;
        bus_data_bytes.delete();
        for (int k = 0; k < 32/8; k++) begin
          bus_data_bytes.push_back(regdata[k*8+:8]);
        end
        if (BUS_DATA_WIDTH > 32) begin
          for (int k = 0; k < (BUS_DATA_WIDTH-32)/8; k++) begin
            bus_data_bytes.push_back('0);
          end
        end
        apb.write(
          .delay(0), .id(0), .address(12'h020), .length(1),
          .size(0), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
        );
        bus_data_bytes.delete();
        do begin
          apb.read(
            .delay(0), .id(0), .address(12'h030), .length(1),
            .size(2), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
          );
          for (int i = 0; i < 4; i++) begin
            regdata[i*8+:8] = bus_data_bytes.pop_front();
          end
        end while (!regdata[0]);
        bus_data_bytes.delete();
        apb.read(
          .delay(0), .id(0), .address(12'h100), .length(8*ARCH_SZ/BUS_DATA_WIDTH),
          .size(2), .burst(0), .lock(0), .prot(0), .data(bus_data_bytes)
        );
        for (int i = 0; i < 8; i++) begin
          for (int j = 0; j < ARCH_SZ/8; j++) begin
            data[j*8+:8] = bus_data_bytes.pop_front();
          end
          hash[i] = data;
        end
        error = 0;
//        for (int i = 0; i < 8; i++) begin
//          error |= (test_set.hash[i] !== hash[i]);
//          $display("expected hash[%0d] = %x; received hash[%0d] = %x", i, test_set.hash[i], i, hash[i]);
//        end
        if (error) begin
          $display("FAIL");
          $stop();
        end else
          $display("valid");
      end while (test_sets.size() > 0);
      $display("SUCCESS");
      $stop();
    end
  endtask : run_apb



  task run ();
    fork
      forever begin
        case (fsm)
          IDLE: begin
            @(posedge slv_bus_if.clk);
            if (testcnt == `N_TEST)
              fsm = WRITE_ALL;
            else
              fsm = READ_ALL;
            testcnt++;
          end
          READ_ALL: begin
            slv_bus_if.read(
                .num(1024/4)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr('0)
              , .q_data(q_rdata)
            );
            @(posedge slv_bus_if.clk);
            $display("READ MEMORY\n=========================================\n");
            for (int i = 0; i < q_rdata.size(); i++) begin
              $display("addr = %3x, data = %8x", i << $clog2(BUS_DATA_WIDTH/8), q_rdata.pop_front());
            end
            $display("=========================================\n");
            q_rdata.delete();
            fsm = WRITE_CFG;
          end
          WRITE_CFG: begin
            q_wdata.delete();
            for (int i = 0; i < ARCH_SZ*8/32*3; i++)
              q_wdata.push_back($random());
            slv_bus_if.write(
                .num(ARCH_SZ*8/32*3)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr(12'h200)
              , .q_data(q_wdata)
            );
            q_wdata.delete();
            q_wdata.push_back($random() & 32'h000000ff | (4 << 8));
            slv_bus_if.write(
                .num(1)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr(12'h010)
              , .q_data(q_wdata)
            );
            q_wdata.delete();
            q_wdata.push_back('1);
            slv_bus_if.write(
                .num(1)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr(12'h040)
              , .q_data(q_wdata)
            );
            fsm = SEND_START;
          end
          SEND_START: begin
            q_wdata.delete();
            q_wdata.push_back(32'hFFFFFF01);
            slv_bus_if.write(
                .num(1)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr(12'h020)
              , .q_data(q_wdata)
            );
            fsm = SEND_ABORT;
          end
          SEND_ABORT: begin
            q_wdata.delete();
            q_wdata.push_back(32'hFFFFFF05);
            slv_bus_if.write(
                .num(1)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr(12'h020)
              , .q_data(q_wdata)
            );
            fsm = WRITE_DATA;
            data_cnt = 0;
          end
          WRITE_DATA: begin
            q_wdata.delete();
            for (int i = 0; i < 4*`ARCH_SZ/BUS_DATA_WIDTH; i++) 
              q_wdata.push_back($random());
            // q_wdata.push_back($random());
            // q_wdata.push_back($random());
            // q_wdata.push_back($random());
            slv_bus_if.write(
                .num(4*`ARCH_SZ/BUS_DATA_WIDTH)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr(12'h140)
              , .q_data(q_wdata)
            );
            fsm = READ_STS;
          end
          READ_STS: begin
            slv_bus_if.read(
                .num(1)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr(12'h030)
              , .q_data(q_rdata)
            );
            data = q_rdata.pop_front();
            if (data[1] && data[12:8] == '0) begin
              data_cnt += 4;
              if (data_cnt == 16)
                fsm = SEND_LAST;
              else
                fsm = WRITE_DATA;
              $display("STS = %8x", data);
              q_rdata.delete();
            end else if (data[4]) begin
              $display("STS = %8x", data);
              q_rdata.delete();
              q_wdata.delete();
              q_wdata.push_back(32'h80000000);
              slv_bus_if.write(
                  .num(1)
                , .burst_enable(1'b0)
                , .burst_type(2'b00)
                , .addr(12'h010)
                , .q_data(q_wdata)
              );
              fsm = IDLE;
            end
          end
          SEND_LAST: begin
            q_wdata.delete();
            q_wdata.push_back(32'hFFFFFF02);
            slv_bus_if.write(
                .num(1)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr(12'h020)
              , .q_data(q_wdata)
            );
            fsm = READ_HASH;
          end
          READ_HASH: begin
            do begin
              @(posedge slv_bus_if.clk);
              data = '0;
              q_rdata.delete();
              slv_bus_if.read(
                  .num(1)
                , .burst_enable(1'b0)
                , .burst_type(2'b00)
                , .addr(12'h030)
                , .q_data(q_rdata)
              );
              data = q_rdata.pop_front();
            end while (~data[0]);
            q_rdata.delete();
            data = '0;
            slv_bus_if.read(
                .num(8*ARCH_SZ/32)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr(12'h100)
              , .q_data(q_rdata)
            );
            for (int i = 0; i < 8*ARCH_SZ/32; i++) begin
              data = q_rdata.pop_front();
              $display("HASH[%0d] = %8x", i, data);
            end
            q_rdata.delete();
            fsm = IDLE;
          end
          WRITE_ALL: begin
            q_wdata.delete();
            $display("WRITE MEMORY\n=========================================\n");
            for (int i = 0; i < 1024/4; i++) begin
              data = $random() & 32'hffffffff;
              $display("addr = %3x, data = %8x", i << $clog2(BUS_DATA_WIDTH/8), data);
              q_wdata.push_back(data);
            end
            $display("=========================================\n");
            slv_bus_if.write(
                .num(1024/4)
              , .burst_enable(1'b0)
              , .burst_type(2'b00)
              , .addr('0)
              , .q_data(q_wdata)
            );
            @(posedge slv_bus_if.clk);
            $stop();
          end
        endcase // fsm
      end
      forever begin
        do @(posedge native_if.clk);
        while (~(native_if.start & native_if.valid & native_if.core_ready));
        native_if.core_ready = '0;
        native_if.read_data(16, q_rdata_native);
        if (!native_if.fault_inj_det)
          native_if.send_hash();
        else begin
          do @(posedge native_if.clk);
          while (native_if.fault_inj_det);
          native_if.core_ready = '1;
        end
      end
      forever begin
        do @(posedge native_if.clk);
        while (~(native_if.ready & native_if.valid));
        @(posedge native_if.clk);
        native_if.fault_inj_det = $urandom_range(0,1);
        if (native_if.fault_inj_det) begin
          repeat (3) @(posedge native_if.clk);
          native_if.fault_inj_det = 0;
        end
        do @(posedge native_if.clk);
        while (~native_if.core_ready);
      end
    join
  endtask : run

endclass : environment

`endif