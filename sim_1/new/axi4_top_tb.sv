`timescale 1ns / 1ps
/*
msg:
88866d5a04c2b81f579962b7293928a6a2458381ef4f022fc2ec7a72422b275e0f5588e36c63f371a4ddd72d89308a6d1a41e5edced3f805720ecea64f09d21b1059ff90b5b1f5e9ff7f3374da3ded1d47eb9f6562d0bff48974c0234e5be5fa1f571c984c5d4dc8edbd13d4fffc20
S32 key:
09a09c09c989a09023b432e28000323f87c79a9008f0ff323225656e3326234fca889df080bc09a3bc54d2af4b23c26e32bb2af423e2a24c4f5233c599c7689e
S64 key without aux_key:
0000000009a09c0900000000c989a0900000000023b432e2000000008000323f0000000087c79a900000000008f0ff32000000003225656e000000003326234f00000000ca889df00000000080bc09a300000000bc54d2af000000004b23c26e0000000032bb2af40000000023e2a24c000000004f5233c50000000099c7689e
*/
module axi4_top_tb;
  localparam logic [3:0] sha_kind = 1 ;
  localparam ADDR_SP_SZ = 12;
  localparam DATA_WIDTH = `FIQSHA_BUS;
  localparam HASH_ADDR = 32'h100;
  localparam awlen_msg = 16;
  
`ifdef CORE_ARCH_S64
    localparam s64 = sha_kind[1]||sha_kind[2];
`else `ifdef CORE_ARCH_S32
    localparam s64 = 1;
`endif `endif
  // Clock and Reset
  logic clk;
  logic resetn;

  // AXI Write Address Channel
  logic [ADDR_SP_SZ-1:0] awaddr;
  logic [7:0] awlen;
  logic [2:0] awsize;
  logic [1:0] awburst;
  logic awvalid;
  logic [3:0] awid = '0;
  logic awready;

  // AXI Write Data Channel
  logic [DATA_WIDTH-1:0] wdata;
  logic wlast;
  logic wvalid;
  logic wready;

  // AXI Write Response Channel
  logic [1:0] bresp;
  logic bvalid;
  logic bready;

  // AXI Read Address Channel
  logic [ADDR_SP_SZ-1:0] araddr;
  logic [7:0] arlen;
  logic [2:0] arsize;
  logic [1:0] arburst;
  logic arvalid;
  logic arready;

  // AXI Read Data Channel
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0] rresp;
  logic rlast;
  logic rvalid;
  logic rready;

  logic irq;
  reg [1023:0] aux_key_i = '0;
  // Test vectors
  reg [DATA_WIDTH-1:0] cfg     [0:0];
  reg [DATA_WIDTH-1:0] ctl     [0:0];
  reg [DATA_WIDTH-1:0] key     [0:31] = '{default: '0};
  reg [DATA_WIDTH-1:0] msg     [awlen_msg];
  reg [DATA_WIDTH-1:0] status  [0:0];
  reg [DATA_WIDTH-1:0] hash_result [0:15][];
  reg [3:0]  random;

  localparam CFG_ADDR  = 32'h010;
  localparam CTL_ADDR  = 32'h020;
  localparam STS_ADDR  = 32'h030;
  localparam DIN_ADDR  = 32'h140;
  localparam KEY_ADDR  = 32'h150;

  // Instantiate DUT
  lw_sha_axi4_top dut (
    .aclk(clk),
    .aresetn(resetn),
    .awaddr(awaddr),
    .awlen(awlen),
    .awsize(awsize),
    .awburst(awburst),
    .awvalid(awvalid),
    .awid(awid),
    .awready(awready),
    .wdata(wdata),
    .wlast(wlast),
    .wvalid(wvalid),
    .wready(wready),
    .bresp(bresp),
    .bvalid(bvalid),
    .bready(bready),
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
    .irq(irq),
    .random_i(random)
`ifdef HMACAUXKEY
   ,.aux_key_i(aux_key_i)
`endif
  );

  // Clock generation
  always #5 clk = ~clk;

// AXI burst write
task axi_write_burst(input logic [31:0] base_addr, input logic [DATA_WIDTH-1:0] data[], input int n);
  begin
    awaddr  <= base_addr;
    awlen   <= n - 1;
    awsize  <= $clog2(DATA_WIDTH/8); // 4 bytes
    awburst <= 2'b00;  // INCR
    awvalid <= 1;
    @(posedge clk);
    while (!awready) @(posedge clk);
    awvalid <= 0;

    for (int i = 0; i < n; i++) begin
      wdata <= data[i];
      wlast <= (i == n - 1);
      wvalid <= 1;
      do @(posedge clk); while (!wready) ;
      wvalid <= 0;
    end

    @(posedge clk);
    while (!bvalid) @(posedge clk);
    bready <= 1;
    @(posedge clk);
    bready <= 0;
    wlast <= 0;
  end
endtask


task axi_read_burst(
  input  logic [31:0] base_addr,
  output logic [DATA_WIDTH-1:0] data[],
  input  int n
);
  int i;
  begin
    if (n <= 0) begin
      $display("WARNING: Requested read burst of size %0d. Ignoring.", n);
      return;
    end

    // Resize dynamic array
    data = new[n];

    // Address channel setup
    araddr  <= base_addr;
    arlen   <= n - 1;
    arsize  <= $clog2(DATA_WIDTH/8);;     // 4 bytes per beat
    arburst <= 2'b01;      // INCR mode
    arvalid <= 1;

    // Wait for address handshake
    @(posedge clk);
    while (!arready) @(posedge clk);
    arvalid <= 0;

    // Data phase
    rready <= 1;
    i = 0;
    while (i < n) begin
      @(posedge clk);
      if (rvalid) begin
        data[i] <= rdata;

        // Check response
        if (rresp != 2'b00) begin
          $display("AXI READ ERROR: RRESP = %b at index %0d", rresp, i);
        end

        // Check for early RLAST
        if (rlast && i != n - 1) begin
          $fatal("AXI PROTOCOL ERROR: RLAST asserted early at index %0d (expected at %0d)", i, n - 1);
        end

        i++;

        // Check for missing RLAST on last beat
        if (i == n && !rlast) begin
          $fatal("AXI PROTOCOL ERROR: RLAST not asserted on last beat at index %0d", i - 1);
        end
      end
    end

    rready <= 0;
  end
endtask

  // Main test sequence
  initial begin
`ifdef CORE_ARCH_S64
    aux_key_i = 'h09a09c09c989a09023b432e28000323f87c79a9008f0ff323225656e3326234fca889df080bc09a3bc54d2af4b23c26e32bb2af423e2a24c4f5233c599c7689e
    `ifndef HMACAUXKEY <<(s64?512:0);`else >> ((`WORD_SIZE*8-`KEY_SIZE > 0) ? (`WORD_SIZE*8-`KEY_SIZE):0);`endif
`else `ifdef CORE_ARCH_S32
    aux_key_i = 'h09a09c09c989a09023b432e28000323f87c79a9008f0ff323225656e3326234fca889df080bc09a3bc54d2af4b23c26e32bb2af423e2a24c4f5233c599c7689e
    `ifndef HMACAUXKEY << 0;`else >> ((`WORD_SIZE*16-`KEY_SIZE > 0) ? (`WORD_SIZE*16-`KEY_SIZE):0); `endif
`endif `endif
    clk = 0;
    resetn = 0;
    awid ='0;
    awvalid = 0;
    wvalid = 0;
    wlast = 0;
    arvalid = 0;
    rready = 0;
    bready = 0;
    msg = '{default: '0};
    repeat (1) @(posedge clk);
    resetn = 1;

    cfg[0] = 32'h80000000;
    axi_write_burst(CFG_ADDR, cfg, 1);
    cfg[0] = 32'h0;
    axi_write_burst(CFG_ADDR, cfg, 1);
    cfg[0] = {28'h1, sha_kind};
    axi_write_burst(CFG_ADDR, cfg, 1);

    ctl[0] = 32'h1;
    axi_write_burst(CTL_ADDR, ctl, 1);
  if (cfg[0][4] == 1) begin
//    for (int i = 0; i < 16; i++) key[i] = 32'h0;
    key [0:15] = {32'h09a09c09, 32'hc989a090,
                  32'h23b432e2, 32'h8000323f,
                  32'h87c79a90, 32'h08f0ff32,
                  32'h3225656e, 32'h3326234f,
                  32'hca889df0, 32'h80bc09a3,
                  32'hbc54d2af, 32'h4b23c26e,
                  32'h32bb2af4, 32'h23e2a24c,
                  32'h4f5233c5, 32'h99c7689e };
`ifdef CORE_ARCH_S64
    axi_write_burst(KEY_ADDR, key, `ifdef APB_W_32 32`else 16 `endif);
`else
    axi_write_burst(KEY_ADDR, key, 16);
`endif
  end
  if (DATA_WIDTH == 32 || `WORD_SIZE == 32 || sha_kind < 4) begin
//  wait (irq);
    msg[0:15] =
    '{'h88866d5a, 'h04c2b81f, 'h579962b7, 'h293928a6,
    'ha2458381, 'hef4f022f, 'hc2ec7a72, 'h422b275e,
    'h0f5588e3, 'h6c63f371, 'ha4ddd72d, 'h89308a6d,
    'h1a41e5ed, 'hced3f805, 'h720ecea6, 'h4f09d21b};
    do axi_write_burst(DIN_ADDR, msg, awlen_msg); while (bresp==2);
 
    wait (irq);
    msg[0:15] = 
    '{'h1059ff90, 'hb5b1f5e9, 'hff7f3374, 'hda3ded1d,
    'h47eb9f65, 'h62d0bff4, 'h8974c023, 'h4e5be5fa,
    'h1f571c98, 'h4c5d4dc8, 'hedbd13d4, 'hfffc2080,
    'h00000000, 'h00000000, 'h00000000, 'h00000378 + (sha_kind[0]?`ifdef CORE_ARCH_S32 'd512 `else !sha_kind[2]&&!sha_kind[3]?'d512:'d1024`endif:0)};
    ctl[0] = 2;
    axi_write_burst(CTL_ADDR, ctl, 1);
    axi_write_burst(DIN_ADDR, msg, awlen_msg);
end else begin
//    wait (irq);
    msg[0:15] =
    '{'h88866d5a04c2b81f, 'h579962b7293928a6,
    'ha2458381ef4f022f, 'hc2ec7a72422b275e,
    'h0f5588e36c63f371, 'ha4ddd72d89308a6d,
    'h1a41e5edced3f805, 'h720ecea64f09d21b,
    'h1059ff90b5b1f5e9, 'hff7f3374da3ded1d,
    'h47eb9f6562d0bff4, 'h8974c0234e5be5fa,
    'h1f571c984c5d4dc8, 'hedbd13d4fffc2080,
    'h0, 'h378 + (sha_kind[0]?`ifdef CORE_ARCH_S32 'd512 `else !sha_kind[2]&&!sha_kind[3]?'d512:'d1024`endif:0)};
    ctl[0] = 2;
    axi_write_burst(CTL_ADDR, ctl, 1);
//    axi_write_burst(DIN_ADDR, msg, awlen_msg);
    do axi_write_burst(DIN_ADDR, msg, awlen_msg); while (bresp==2);
end
    do axi_read_burst(STS_ADDR, status, 1);
    while (status[0][4]);

// S64-based configurations
`ifdef CORE_ARCH_S64
  `ifdef APB_W_32
    axi_read_burst(HASH_ADDR, hash_result[0], 16);
    $display("Hash result word = %h%h%h%h%h%h%h%h%h%h%h%h%h%h%h%h",
      hash_result[0][15], hash_result[0][14], hash_result[0][13], hash_result[0][12],
      hash_result[0][11], hash_result[0][10], hash_result[0][9],  hash_result[0][8],
      hash_result[0][7],  hash_result[0][6],  hash_result[0][5],  hash_result[0][4],
      hash_result[0][3],  hash_result[0][2],  hash_result[0][1],  hash_result[0][0]);
  `elsif APB_W_64
    axi_read_burst(HASH_ADDR, hash_result[0], 8);
    $display("Hash result word = %h%h%h%h%h%h%h%h",
      hash_result[0][7], hash_result[0][6], hash_result[0][5], hash_result[0][4],
      hash_result[0][3], hash_result[0][2], hash_result[0][1], hash_result[0][0]);
  `elsif APB_W_128
    axi_read_burst(HASH_ADDR, hash_result[0], 4);
    $display("Hash result word = %h%h%h%h",
      hash_result[0][3], hash_result[0][2], hash_result[0][1], hash_result[0][0]);
  `endif
`endif

// S32-based configurations
`ifdef CORE_ARCH_S32
  `ifdef APB_W_32
    axi_read_burst(HASH_ADDR, hash_result[0], 8);
    $display("Hash result word = %h%h%h%h%h%h%h%h",
      hash_result[0][7],  hash_result[0][6],  hash_result[0][5],  hash_result[0][4],
      hash_result[0][3],  hash_result[0][2],  hash_result[0][1],  hash_result[0][0]);
  `elsif APB_W_64
    axi_read_burst(HASH_ADDR, hash_result[0], 4);
    $display("Hash result word = %h%h%h%h",
      hash_result[0][3], hash_result[0][2], hash_result[0][1], hash_result[0][0]);
  `elsif APB_W_128
    axi_read_burst(HASH_ADDR, hash_result[0], 2);
    $display("Hash result word = %h%h",
      hash_result[0][1], hash_result[0][0]);
  `endif
`endif

//`ifdef CORE_ARCH_S64
//      for (int i = 0; i < 16; i++) begin
//        axi_read_burst('h100 + 4*i, hash_result[i], 1);
//      end
//       $display("Hash result word = %h%h%h%h%h%h%h%h%h%h%h%h%h%h%h%h",
//       hash_result[15][0], hash_result[14][0], hash_result[13][0], hash_result[12][0],
//       hash_result[11][0],hash_result[10][0], hash_result[9][0], hash_result[8][0],
//       hash_result[7][0], hash_result[6][0], hash_result[5][0], hash_result[4][0],
//       hash_result[3][0],hash_result[2][0], hash_result[1][0], hash_result[0][0]);
//`else `ifdef CORE_ARCH_S32
//        for (int i = 0; i < 8; i++) begin
//          axi_read_burst('h100 + (`ifdef CORE_ARCH_S32 4 `else 8 `endif)*i, hash_result[i], 1);
//        end
//       $display("Hash result word = %h%h%h%h%h%h%h%h",
//       hash_result[7][0], hash_result[6][0], hash_result[5][0], hash_result[4][0],
//       hash_result[3][0],hash_result[2][0], hash_result[1][0], hash_result[0][0]);
//`endif `endif

//    $finish;
  end
  always @(posedge clk) random <= $random % 16;

endmodule