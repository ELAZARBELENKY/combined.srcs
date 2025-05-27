`timescale 1ns / 1ps
`include "../../sources_1/new/defines.v"

module ahb_top_tb();
  parameter BUS_WIDTH   = `FIQSHA_BUS;
  parameter ADDR_SP_SZ  = 12;
  parameter HASH_WIDTH = `WORD_SIZE*8;
  parameter FIQSHA_BUS_DATA_WIDTH = `FIQSHA_BUS;

  // Constants for SHA256 registers
  localparam ID_ADDR   = 12'h000;
  localparam CFG_ADDR  = 12'h010;
  localparam CTL_ADDR  = 12'h020;
  localparam STS_ADDR  = 12'h030;
  localparam IE_ADDR   = 12'h040;
  localparam HASH_ADDR = 12'h100;
  localparam DIN_ADDR  = 12'h140;
  localparam KEY_ADDR  = 12'h150;

  localparam [3:0] sha_kind = 'h5;
  `ifdef CORE_ARCH_S64
    localparam s64 = sha_kind[1]||sha_kind[2];
  `else `ifdef CORE_ARCH_S32
    localparam s64 = 1;
  `endif `endif

  // Clock and reset
  logic hclk = 0;
  logic hresetn;

  // AHB signals
  logic [ADDR_SP_SZ-1:0] haddr;
  logic [2:0]            hburst = 3'b000;
  logic [2:0]            hsize = (BUS_WIDTH == 64) ? 3'b011 : 3'b010;
  logic [1:0]            htrans;
  logic [BUS_WIDTH-1:0]  hwdata;
  logic                  hwrite;
  logic                  hsel = 1;
  logic                  hready = 1;
  logic [BUS_WIDTH-1:0]  hrdata;
  logic                  hreadyout;
  logic                  hresp;
  logic [3:0]            random_i;
  logic                  irq_o;
  logic                  dma_wr_req_o;
  logic                  dma_rd_req_o;
  logic [31:0] cfg_val;
//`ifdef HMACAUXKEY
//  logic [`KEY_SIZE-1:0]    aux_key_i;
//`endif
  logic [BUS_WIDTH-1:0]  data[];
  reg [1023:0] aux_key_i = '0;
  reg [FIQSHA_BUS_DATA_WIDTH - 1:0] avl[HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH - 1:0];
  reg [FIQSHA_BUS_DATA_WIDTH - 1:0] hash_result[HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH - 1:0];
  // Clock generation
  always
    #5 hclk = ~hclk;

  // DUT instantiation
  lw_sha_ahb_top dut (.*);
  
task automatic ahb_single_write(
  input logic [11:0] addr,              // Address to write to
  input logic [DATA_WIDTH-1:0] data     // Data to write
);
  // Wait for previous transfer completion and OKAY response
  wait (hready && hresp == 0);

  // Address Phase Setup ----------------------------------------
  hsel   <= 1'b1;       // Select this slave
  hwrite <= 1'b1;       // Write operation
  haddr  <= addr;       // Address
  hburst <= 3'b000;     // SINGLE transfer
  htrans <= 2'b10;      // NONSEQ transfer (valid transfer)

  // Wait for address phase acceptance (HREADY = 1)
  @(posedge hclk iff hready);

  // Data Phase -------------------------------------------------
  hwdata <= data;       // Drive write data

  // Keep data stable until transfer completes
  do begin
    @(posedge hclk);
  end while (!hready);  // Wait for HREADY=1 (data phase completion)

  // Cleanup ----------------------------------------------------
  htrans <= 2'b00;      // IDLE transfer type
  hsel   <= 1'b0;       // Deselect slave
  hwrite <= 1'b0;       // Clear write signal

  // Optional: Wait 1 cycle for clean bus state (protocol-compliant)
  @(posedge hclk);
endtask

task ahb_read(
  input logic [ADDR_SP_SZ-1:0] addr,
  output logic [FIQSHA_BUS_DATA_WIDTH - 1:0] data[HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH - 1:0],
  input int unsigned length
);
  int i;
  begin
    // First address phase
    hsel   <= 1;
    hwrite <= 0;
    haddr  <= addr;
    hburst <= (length == 1) ? 3'b000 : (length == 4) ? 3'b101 : 3'b100;
    htrans <= 2'b10; // NONSEQ first beat
    @(posedge hclk);
    @(posedge hclk);
    
    for (i = 0; i < length; i++) begin
      // Wait for current data phase and capture
      while (!hreadyout) @(posedge hclk);
      data[i] <= hrdata;
      
      // Setup next address phase (if not last beat)
      if (i < length - 1) begin
        htrans <= 2'b11; // SEQ
        @(posedge hclk);
      end
    end
    
    // Clean termination
    htrans <= 2'b00;
    hsel <= 0;
    hburst <= 3'b000;
    @(posedge hclk);
  end
endtask
    
    // SHA-256 Test Case (Precise, with Padding)
  task automatic sha256_test (input logic new_key);
  logic half_words;
    //input [FIQSHA_BUS_DATA_WIDTH - 1:0] test_data;
    begin

      // Padded data for "abc" (512 bits = 64 bytes)
      localparam string input_str = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstuabcdefghigklmnopqrstuvwxyz";
//      localparam string input_str = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu";
//      localparam string input_str = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
//      localparam string input_str = "abc";
      localparam length = input_str.len()*8;
`ifdef CORE_ARCH_S64

                  /* FOR S64 */
        localparam num = length >= `WORD_SIZE*14 ?
        16<<($clog2(length+`WORD_SIZE*2+1)-($clog2(`WORD_SIZE)+4)):16;

                  /* FOR S32 */  
//      localparam int num = length >= `WORD_SIZE/(s64?1:2)*14 ?
//        ($clog2(length+`WORD_SIZE/(s64?1:2)*2+1)-8)*16:16;

`else `ifdef CORE_ARCH_S32
      localparam int num = length >= `WORD_SIZE/(s64?1:2)*14 ?
          ($clog2(length+`WORD_SIZE/(s64?1:2)*2+1)-8)*16:16;
`endif `endif
      reg [num*`WORD_SIZE/(s64?1:2)-1:0] padded_data = 0;
      
      logic [length-1:0] hex_value;
      // Converting each character to its hexadecimal value
      for (int i = 0; i < length; i++) begin
          hex_value[(length-1 - i * 8) -: 8] = input_str[i];
      end
      padded_data[num*`WORD_SIZE/(s64?1:2)-1-:length+1] = {hex_value,1'b1};
      padded_data[15:0] = length + ((sha_kind[0]) ? `WORD_SIZE/(s64?1:2)*16:0);

      // 1. Reset the core
//      ahb_single_write(CFG_ADDR, 32'h1);
//      repeat(2) @(posedge hclk);
//      ahb_single_write(CFG_ADDR, 32'h0);
//      repeat(2) @(posedge hclk);

      // 2. Configure for OPCODE and strating operation
      
      cfg_val = {27'b0, new_key, sha_kind[3:0]};
      ahb_single_write(CFG_ADDR, '{cfg_val}); // OPCODE = sha_kind
      ahb_single_write(CTL_ADDR, {32'h1});  // CTL.INIT = 1
    
    if (new_key&&sha_kind[0]) begin
`ifndef HMACAUXKEY `ifdef CORE_ARCH_S64
      // 3. Send KEY (Padded - 512 bits)
      half_words = (`FIQSHA_BUS == 32 && s64)|| !s64;
      for (int i = 0; i < (half_words&&s64?32:16); i++) begin
        if (half_words) ahb_single_write(KEY_ADDR,
          aux_key_i[(16*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE/2)) -: `WORD_SIZE/2]); // Write data segment
        else ahb_single_write(KEY_ADDR,
          aux_key_i[(16*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]); // Write data segment
//        if (i == 2) pstrb <= 'h81;
//        else pstrb <= '1;
        if (hresp) i--;
      end
`else `ifdef CORE_ARCH_S32
      
      for (int i = 0; i < 16; i++) begin
      data[i] = aux_key_i[(16*`WORD_SIZE-1 - (i * `WORD_SIZE)) -: `WORD_SIZE];
      end
//      ahb_single_write(KEY_ADDR,data); // Write data segment

`endif `endif `endif 
    end
//#70 ahb_write(CTL_ADDR, 32'h2);
      // 4. Send Data (Padded - 512 bits)
`ifdef CORE_ARCH_S64
      half_words = (`FIQSHA_BUS == 32 && s64) || !s64;
      for (int i = 0; i < num*(half_words&&s64?2:1); i++) begin
          if (half_words) ahb_single_write(DIN_ADDR, {padded_data[(num*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE/2)) -: `WORD_SIZE/2]}); // Write data segment
          else ahb_single_write(DIN_ADDR, {padded_data[(num*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]}); // Write data segment
          if (i == num*(half_words&&s64?2:1)-10) ahb_single_write(CTL_ADDR, {32'h2});
          if (hresp) i--;
//          if (hresp)  ahb_single_write(STS_ADDR, 32'h8);
      end
`else `ifdef CORE_ARCH_S32
      for (int i = 0; i < num; i++) begin
        ahb_single_write(DIN_ADDR, {padded_data[(num*`WORD_SIZE-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]}); // Write data segment
        if (i == num-10) ahb_single_write(CTL_ADDR, {32'h2});
        if (hresp) i--;
//        if (hresp) ahb_single_write(STS_ADDR, 32'h8);
      end
`endif `endif

      // 5. Wait for result
      do ahb_read(STS_ADDR,avl,1); while (avl[0][0] != 1'b1);
      
      // 6. Read the hash result
//      for (int i = 0; i < HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH; i++) begin
        ahb_read(HASH_ADDR, hash_result, HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH);
//      end
   ahb_single_write(STS_ADDR, {32'h1});
      $display("SHA-256 Test Result:");
      $display("input data(UTF-8): %s", input_str);
      $display("input data - Hexa: %h", hex_value);
      $display("input data padded: %h", padded_data);
//`ifdef HMACAUXKEY
//if (`KEY_SIZE != 0)
//      $display("aux_key: %h", aux_key_i[`KEY_SIZE-1:0]);
//`endif
      if (new_key) $display("aux_key: %h", aux_key_i[512-1:0]);
      $display("num of blocks: %d", num*32/(`WORD_SIZE/(s64?1:2)*16));
      $display("SHA-kind: %h", sha_kind);
//      $display("Hash Result: %h", hash_result);
$write("Hash Result: ");
for (int i = HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH-1; i >=0 ; i--) begin
$write("%h", hash_result[i]);
end
$write("\n");

    end
  endtask
  
logic [31:0] val[];
  
   initial begin
    hclk = 0;
    hresetn = 1;
    hsel = 0;
//    henable = 0;
    hwrite = 0;
    haddr = 0;
    hwdata = 0;

    // Run tests
    repeat(20) @(posedge hclk); // Clock some cycles
    hresetn = 1;
    repeat(2) @(posedge hclk); // Wait after reset
    
//ahb_single_write(CFG_ADDR, {32'h80000000});
//ahb_single_write(CFG_ADDR, {32'h80000000});
//@(posedge hclk)
//ahb_single_write(CFG_ADDR, {32'h0});
//ahb_single_write(IE_ADDR, {32'hA5A5A5A5});
//ahb_read(IE_ADDR, val,1);
`ifdef CORE_ARCH_S64
    aux_key_i = 'h09a09c09c989a09023b432e28000323f87c79a9008f0ff323225656e3326234fca889df080bc09a3bc54d2af4b23c26e32bb2af423e2a24c4f5233c599c7689e
    `ifndef HMACAUXKEY <<(s64?512:0);`else >> ((`WORD_SIZE*8-`KEY_SIZE > 0) ? (`WORD_SIZE*8-`KEY_SIZE):0);`endif
`else `ifdef CORE_ARCH_S32
    aux_key_i = 'h09a09c09c989a09023b432e28000323f87c79a9008f0ff323225656e3326234fca889df080bc09a3bc54d2af4b23c26e32bb2af423e2a24c4f5233c599c7689e
    `ifndef HMACAUXKEY << 0;`else >> ((`WORD_SIZE*16-`KEY_SIZE > 0) ? (`WORD_SIZE*16-`KEY_SIZE):0); `endif
`endif `endif

    sha256_test(0); // No input argument
    repeat(200) @(posedge hclk);
    sha256_test(1); // No input argument
    repeat(200) @(posedge hclk);
`ifdef CORE_ARCH_S64
    aux_key_i = 'hb6e67e93094324798b7898a97df23467f2923890fc3a09898e9e809c989b808ad9a346fe8904324344534ba69896350c78f7291ca98e09389240b98c08d8d890
`ifndef HMACAUXKEY <<(s64?512:0);`else >> ((`WORD_SIZE*8-`KEY_SIZE > 0) ? (`WORD_SIZE*8-`KEY_SIZE):0);`endif
`else `ifdef CORE_ARCH_S32
    aux_key_i = 'hb6e67e93094324798b7898a97df23467f2923890fc3a09898e9e809c989b808ad9a346fe8904324344534ba69896350c78f7291ca98e09389240b98c08d8d890
    `ifndef HMACAUXKEY << 0;`else >> ((`WORD_SIZE*16-`KEY_SIZE > 0) ? (`WORD_SIZE*16-`KEY_SIZE):0); `endif
`endif `endif
    sha256_test(1); // No input argument
  end
  always @(posedge hclk) random_i <= $random % 16;
endmodule