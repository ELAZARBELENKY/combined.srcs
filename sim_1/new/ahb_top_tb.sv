`timescale 1ns / 1ps
`include "../../sources_1/new/defines.v"

module ahb_top_tb();
  parameter BUS_WIDTH   = 32;
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
  logic                  hsel;
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
  reg [FIQSHA_BUS_DATA_WIDTH - 1:0] avl;
  reg [HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH - 1:0][FIQSHA_BUS_DATA_WIDTH - 1:0] hash_result;
  // Clock generation
  always
    #5 hclk = ~hclk;

  // DUT instantiation
  lw_sha_ahb_top dut (.*);

  // Full AHB write transaction task (single or burst)
task automatic ahb_write(
  input logic [11:0] addr,         // Starting address
  input logic [DATA_WIDTH-1:0] data[],       // Data array to write
  input int unsigned length                  // Number of beats in burst (1=single)
);
  int unsigned i;
  logic [11:0] current_addr;
  logic [1:0] transfer_type;
  logic [2:0] burst_type = 3'b001;     // Default: INCR (001)
  logic [2:0] size = 3'b010;           // Default: 32-bit (010)
  
  // Calculate transfer increment based on size
  int addr_incr;
  case (size)
    3'b000: addr_incr = 1;  // 8-bit
    3'b001: addr_incr = 2;  // 16-bit 
    3'b010: addr_incr = 4;  // 32-bit
    3'b011: addr_incr = 8;  // 64-bit
    default: addr_incr = 4; // Default to 32-bit
  endcase

  // Address phase for first transfer
  @(posedge hclk);
  
  // Setup control signals
  hsel   <= 1'b1;
  hwrite <= 1'b1;
  haddr  <= addr;
  hsize  <= size;
  
  // Set burst type based on length and requested burst type
  if (length == 1)
    hburst <= 3'b000;  // SINGLE
  else
    hburst <= burst_type;  // Use specified burst type
    
  htrans <= 2'b10;     // NONSEQ for first transfer
  
  // Wait for address phase to complete
  @(posedge hclk);
  
  // First data phase occurs now
  hwdata <= data[0];
  
  // If more than one beat, continue with burst
  for (i = 1; i < length; i++) begin
    // Setup address phase for next transfer while current data phase is happening
    current_addr = calculate_next_address(addr, addr_incr, burst_type, i);
    haddr  <= current_addr;
    htrans <= 2'b11;   // SEQ for subsequent beats
    
    // Wait for next clock - both completing current data phase and setting up next address phase
    @(posedge hclk);
    
    // Output data for current beat
    hwdata <= data[i];
    
    // Check for HREADY (slave might insert wait states)
    while (!hready) begin
      @(posedge hclk);
      // Keep data stable during wait states
      hwdata <= data[i];
    end
  end
  
  // Complete the final data phase
  @(posedge hclk);
  
  // Wait for final data phase to complete if slave inserts wait states
  while (!hready) begin
    @(posedge hclk);
  end
  
  // Return to idle state
  htrans <= 2'b00;     // IDLE
  hburst <= 3'b000;    // SINGLE
  hsel   <= 1'b0;      // Deselect slave
  hwrite <= 1'b0;      // Clear write signal
  
  // One more cycle to ensure clean transition
  @(posedge hclk);
endtask

// Helper function to calculate next address based on burst type
function automatic logic [11:0] calculate_next_address(
  input logic [11:0] start_addr,
  input int addr_incr,
  input logic [2:0] burst_type,
  input int transfer_number
);
  logic [11:0] next_addr;
  logic [11:0] wrap_mask;
  
  case (burst_type)
    3'b000: // SINGLE
      next_addr = start_addr;
      
    3'b001: // INCR (undefined length)
      next_addr = start_addr + (transfer_number * addr_incr);
      
    3'b010: begin // WRAP4
      // Calculate wrap boundary for WRAP4 (4*size aligned)
      wrap_mask = (4 * addr_incr) - 1;
      next_addr = (start_addr & ~wrap_mask) | ((start_addr + transfer_number * addr_incr) & wrap_mask);
    end
    
    3'b011: // INCR4
      next_addr = start_addr + (transfer_number * addr_incr);
      
    3'b100: begin // WRAP8
      // Calculate wrap boundary for WRAP8 (8*size aligned)
      wrap_mask = (8 * addr_incr) - 1;
      next_addr = (start_addr & ~wrap_mask) | ((start_addr + transfer_number * addr_incr) & wrap_mask);
    end
    
    3'b101: // INCR8
      next_addr = start_addr + (transfer_number * addr_incr);
      
    3'b110: begin // WRAP16
      // Calculate wrap boundary for WRAP16 (16*size aligned)
      wrap_mask = (16 * addr_incr) - 1;
      next_addr = (start_addr & ~wrap_mask) | ((start_addr + transfer_number * addr_incr) & wrap_mask);
    end
    
    3'b111: // INCR16
      next_addr = start_addr + (transfer_number * addr_incr);
      
    default: // Default to INCR
      next_addr = start_addr + (transfer_number * addr_incr);
  endcase
  
  return next_addr;
endfunction

  // Full AHB read transaction task (single or burst)
  task ahb_read(
    input logic [ADDR_SP_SZ-1:0] addr,
    output logic [FIQSHA_BUS_DATA_WIDTH - 1:0] rdata,
    input int unsigned length
  );
    int i;
    begin
      hsel   <= 1;
      hwrite <= 0;
      haddr  <= addr;
      hburst <= (length == 1) ? 3'b000 : (length == 4) ? 3'b011 : 3'b111;
      htrans <= 2'b10; // NONSEQ first beat
      @(posedge hclk);

      for (i = 0; i < length; i++) begin
        if (i > 0) begin
          haddr <= addr + i*4;
          htrans <= 2'b11; // SEQ for bursts
          @(posedge hclk);
        end
        // wait for ready, then latch data
        while (!hreadyout) @(posedge hclk);
        data[i] <= hrdata;
      end

      // finish burst
      htrans <= 2'b00;
      hburst <= 3'b000;
      hsel   <= 0;
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
//        localparam num = length >= `WORD_SIZE*14 ?
//        16<<($clog2(length+`WORD_SIZE*2+1)-($clog2(`WORD_SIZE)+4)):16;

                  /* FOR S32 */  
      localparam int num = length >= `WORD_SIZE/(s64?1:2)*14 ?
        ($clog2(length+`WORD_SIZE/(s64?1:2)*2+1)-8)*16:16;

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
//      ahb_write(CFG_ADDR, 32'h1);
//      repeat(2) @(posedge hclk);
//      ahb_write(CFG_ADDR, 32'h0);
//      repeat(2) @(posedge hclk);

      // 2. Configure for OPCODE and strating operation
      
      cfg_val = {27'b0, new_key, sha_kind[3:0]};
      ahb_write(CFG_ADDR, '{cfg_val}, 1); // OPCODE = sha_kind
      ahb_write(CTL_ADDR, {32'h1},1);  // CTL.INIT = 1
    
    if (new_key&&sha_kind[0]) begin
`ifndef HMACAUXKEY `ifdef CORE_ARCH_S64
      // 3. Send KEY (Padded - 512 bits)
      half_words = (`FIQSHA_BUS == 32 && s64)|| !s64;
      for (int i = 0; i < (half_words&&s64?32:16); i++) begin
        if (half_words) ahb_write(KEY_ADDR,
          aux_key_i[(16*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE/2)) -: `WORD_SIZE/2],1); // Write data segment
        else ahb_write(KEY_ADDR,
          aux_key_i[(16*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE)) -: `WORD_SIZE],1); // Write data segment
//        if (i == 2) pstrb <= 'h81;
//        else pstrb <= '1;
        if (hresp) i--;
      end
`else `ifdef CORE_ARCH_S32
      
      for (int i = 0; i < 16; i++) begin
      data[i] = aux_key_i[(16*`WORD_SIZE-1 - (i * `WORD_SIZE)) -: `WORD_SIZE];
      end
      ahb_write(KEY_ADDR,data,16); // Write data segment

`endif `endif `endif 
    end
//#70 ahb_write(CTL_ADDR, 32'h2);
      // 4. Send Data (Padded - 512 bits)
`ifdef CORE_ARCH_S64
      half_words = (`FIQSHA_BUS == 32 && s64) || !s64;
      for (int i = 0; i < num*(half_words&&s64?2:1); i++) begin
          if (half_words) ahb_write(DIN_ADDR, {padded_data[(num*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE/2)) -: `WORD_SIZE/2]},1); // Write data segment
          else ahb_write(DIN_ADDR, {padded_data[(num*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]},1); // Write data segment
          if (i == num*(half_words&&s64?2:1)-10) ahb_write(CTL_ADDR, {32'h2},1);
          if (hresp) i--;
//          if (hresp)  ahb_write(STS_ADDR, 32'h8);
      end
`else `ifdef CORE_ARCH_S32
      for (int i = 0; i < num; i++) begin
        ahb_write(DIN_ADDR, {padded_data[(num*`WORD_SIZE-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]},1); // Write data segment
        if (i == num-10) ahb_write(CTL_ADDR, {32'h2},1);
        if (hresp) i--;
//        if (hresp) ahb_write(STS_ADDR, 32'h8);
      end
`endif `endif

      // 5. Wait for result
      do ahb_read(STS_ADDR,avl,1); while (avl[0] != 1'b1);
      
      // 6. Read the hash result
      for (int i = 0; i < HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH; i++) begin
        ahb_read(HASH_ADDR, hash_result, HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH);
      end
   ahb_write(STS_ADDR, {32'h1},1);
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
for (int i = 0; i < HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH; i++) begin
$write("%h", hash_result[i]);
end
$write("\n");

    end
  endtask
  
logic [31:0] val[];
  
   initial begin
    hclk = 0;
    hresetn = 0;
    hsel = 0;
//    henable = 0;
    hwrite = 0;
    haddr = 0;
    hwdata = 0;

    // Run tests
    hresetn = 0;
    repeat(20) @(posedge hclk); // Clock some cycles
    hresetn = 1;
    repeat(2) @(posedge hclk); // Wait after reset
    
//ahb_write(CFG_ADDR, {32'h80000000},1);
ahb_write(CFG_ADDR, {32'h80000000},1);
//@(posedge hclk)
ahb_write(CFG_ADDR, {32'h0},1);
ahb_write(IE_ADDR, {32'hA5A5A5A5},1);
//ahb_read(IE_ADDR, val,1);
`ifdef CORE_ARCH_S64
    aux_key_i = 'h09a09c09c989a09023b432e28000323f87c79a9008f0ff323225656e3326234fca889df080bc09a3bc54d2af4b23c26e32bb2af423e2a24c4f5233c599c7689e
    `ifndef HMACAUXKEY <<(s64?512:0);`else >> ((`WORD_SIZE*8-`KEY_SIZE > 0) ? (`WORD_SIZE*8-`KEY_SIZE):0);`endif
`else `ifdef CORE_ARCH_S32
    aux_key_i = 'h09a09c09c989a09023b432e28000323f87c79a9008f0ff323225656e3326234fca889df080bc09a3bc54d2af4b23c26e32bb2af423e2a24c4f5233c599c7689e
    `ifndef HMACAUXKEY << 0;`else >> ((`WORD_SIZE*16-`KEY_SIZE > 0) ? (`WORD_SIZE*16-`KEY_SIZE):0); `endif
`endif `endif

    sha256_test(1); // No input argument
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