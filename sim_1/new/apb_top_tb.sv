module apb_top_tb;
`include "../../sources_1/new/defines.v"
  // Parameters
  parameter FIQSHA_BUS_DATA_WIDTH = `FIQSHA_BUS;
  parameter ADDR_WIDTH = 12;
  parameter HASH_WIDTH = `WORD_SIZE*8;
localparam [31:0] sha_kind = 'ha;
`ifdef CORE_ARCH_S64
    localparam s64 = sha_kind[1]||sha_kind[2];
`else `ifdef CORE_ARCH_S32
    localparam s64 = 1;
`endif `endif
  // Signals
  reg pclk = 0;
  reg presetn;
  reg psel;
  reg penable;
  reg pwrite;
  reg [ADDR_WIDTH-1:0] paddr;
  reg [FIQSHA_BUS_DATA_WIDTH-1:0] pwdata;
  reg [FIQSHA_BUS_DATA_WIDTH/8-1:0] pstrb = '1;
  wire pready;
  wire [FIQSHA_BUS_DATA_WIDTH-1:0] prdata;
  wire pslverr;
  wire irq_o;
  reg [1023:0] aux_key_i = '0;
  reg [1:0] random_i;
  wire dma_wr_req_o;
  wire dma_rd_req_o;

  // Testbench Execution
  reg [HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH - 1:0][FIQSHA_BUS_DATA_WIDTH - 1:0] hash_result;
  reg [FIQSHA_BUS_DATA_WIDTH - 1:0] avl=0;
  // Instantiate
  lw_sha_apb_top dut (
    .pclk(pclk),
    .presetn(presetn),
    .paddr(paddr),
    .psel(psel),
    .penable(penable),
    .pwrite(pwrite),
    .pwdata(pwdata),
    .pstrb(pstrb),
    .pready(pready),
    .prdata(prdata),
    .pslverr(pslverr),
    .irq_o(irq_o),
`ifdef HMACAUXKEY
    .aux_key_i(aux_key_i),
`endif
    .random_i(random_i),
    .dma_wr_req_o(dma_wr_req_o),
    .dma_rd_req_o(dma_rd_req_o)
  );

  // Clock
  initial forever #5 pclk = ~pclk;

  // Reset
  initial begin
    presetn = 0;
    @(posedge pclk);
    presetn = 1;
  end

  // APB Write Task (Cycle-Accurate)
  task apb_write;
    input [ADDR_WIDTH - 1:0] addr;
    input [FIQSHA_BUS_DATA_WIDTH - 1:0] wdata;
    begin
//      #1
      psel <= 1;           // Select the slave
      paddr <= addr;       // Set address
      pwdata <= wdata;       // Set write data
      pwrite <= 1;         // Write transaction
      penable <= 0;        // Setup phase - penable LOW
//      #10
      @(posedge pclk);
//      if ((addr == 'h140||addr == 'h150) && ~pready)
//      wait (pready==1); // Wait for slave to be ready

      penable <= 1;        // Enable phase - penable HIGH
//      #10
      @(posedge pclk);
wait (pready==1);
      penable <= 0;        // End of Enable phase
      psel <= 0;         // Deselect the slave
//      @(posedge pclk);     // Wait for pready      @(posedge pclk);
    end
  endtask

// APB Read Task (Cycle-Accurate)
task apb_read;
  input [ADDR_WIDTH - 1:0] addr;
  output reg [FIQSHA_BUS_DATA_WIDTH - 1:0] rdata;
  begin
  #1
//    wait(pready == 1);   // Wait for slave to be ready
    psel = 1;            // Select slave
    paddr = addr;        // Set address
    pwrite = 0;          // Read transaction
    penable = 0;         // Setup phase
//#10
    @(posedge pclk);
    penable = 1;         // Enable phase
    wait(pready == 1);
//#10
      @(posedge pclk);
//      wait(pready == 1);
       // Wait for slave ready (data available)
    rdata = prdata;      // Capture read data

    // Clear signals
    psel = 0;            // Deselect slave
    penable = 0;         // Disable transaction
    paddr = '0;          // Clear address (optional, for safety)
  end
endtask

  // SHA-256 Test Case (Precise, with Padding)
  task automatic sha256_test (input new_key);
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

        localparam num = length >= `WORD_SIZE*14 ?
        16<<($clog2(length+`WORD_SIZE*2+1)-($clog2(`WORD_SIZE)+4)):16;

                  /*  ?FOR S32? ?FOR S64?  */

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
`ifdef CORE_ARCH_S64
      padded_data[15:0] = length + ((sha_kind > 5) ? `WORD_SIZE/(s64?1:2)*16:0);
`else `ifdef CORE_ARCH_S32
      padded_data[15:0] = length + ((sha_kind > 1) ? `WORD_SIZE/(s64?1:2)*16:0);
`endif `endif
      // 1. Reset the core
      apb_write('h10, 32'h1);
      repeat(2) @(posedge pclk);
      apb_write('h10, 32'h0);
      repeat(2) @(posedge pclk);

      // 2. Configure for OPCODE and strating operation
      apb_write('h10, sha_kind); // OPCODE = sha_kind
      apb_write('h20, 32'h1);  // CTL.INIT = 1
    
    if (new_key) begin
`ifdef CORE_ARCH_S64 `ifndef HMACAUXKEY
      // 3. Send KEY (Padded - 512 bits)
      half_words = (`FIQSHA_BUS == 32 && s64)|| !s64;
      for (int i = 0; i < (half_words&&s64?32:16); i++) begin
        if (half_words) apb_write('h150,
          aux_key_i[(16*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE/2)) -: `WORD_SIZE/2]); // Write data segment
        else apb_write('h150,
          aux_key_i[(16*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]); // Write data segment
//        if (i == 2) pstrb <= 'h81;
//        else pstrb <= '1;
        if (pslverr) i--;
      end
`else `ifdef CORE_ARCH_S32
      for (int i = 0; i < 16; i++) begin
          apb_write('h150,
          aux_key_i[(16*`WORD_SIZE-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]); // Write data segment
        if (pslverr) i--;
      end
`endif `endif `endif 
    end

      // 4. Send Data (Padded - 512 bits)
`ifdef CORE_ARCH_S64
      half_words = (`FIQSHA_BUS == 32 && s64) || !s64;
      for (int i = 0; i < num*(half_words&&s64?2:1); i++) begin
          if (half_words) apb_write('h140, padded_data[(num*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE/2)) -: `WORD_SIZE/2]); // Write data segment
          else apb_write('h140, padded_data[(num*`WORD_SIZE/(s64?1:2)-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]); // Write data segment
          if (i == num*(half_words&&s64?2:1)-10) apb_write('h20, 32'h2);
//          if (i == 10)  apb_write('h30, 32'h4);
        if (pslverr) i--;
      end
`else `ifdef CORE_ARCH_S32
      for (int i = 0; i < num; i++) begin
          apb_write('h140, padded_data[(num*`WORD_SIZE-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]); // Write data segment
          if (i == num-10) apb_write('h20, 32'h2);
        if (pslverr) i--;
      end
`endif `endif

      // 5. Wait for result
      do apb_read('h030,avl); while (avl[0] !== 1'b1);

      // 6. Read the hash result
      for (int i = 0; i < HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH; i++) begin
        apb_read('h100 + (i * (FIQSHA_BUS_DATA_WIDTH / 8)), hash_result[i]);
      end
  
      $display("SHA-256 Test Result:");
      $display("input data(UTF-8): %s", input_str);
      $display("input data - Hexa: %h", hex_value);
      $display("input data padded: %h", padded_data);
`ifdef HMACAUXKEY
      $display("aux_key: %h", aux_key_i[`KEY_SIZE-1:0]);
`endif
      $display("num of blocks: %d", num*32/(`WORD_SIZE/(s64?1:2)*16));
      $display("Hash Result: %h", hash_result);
  
    end
  endtask
  initial begin
    pclk = 0;
    presetn = 0;
    psel = 0;
    penable = 0;
    pwrite = 0;
    paddr = 0;
    pwdata = 0;
`ifdef CORE_ARCH_S64
    aux_key_i = 'h09a09c09c989a09023b432e28000323f87c79a9008f0ff323225656e3326234fca889df080bc09a3bc54d2af4b23c26e32bb2af423e2a24c4f5233c599c7689e`ifndef HMACAUXKEY <<(s64?512:0);`else ;
`endif
`else `ifdef CORE_ARCH_S32
    aux_key_i = 'h09a09c09c989a09023b432e28000323f87c79a9008f0ff323225656e3326234fca889df080bc09a3bc54d2af4b23c26e32bb2af423e2a24c4f5233c599c7689e;
`endif `endif
    // Run tests
    presetn = 0;
    repeat(2) @(posedge pclk); // Clock some cycles
    presetn = 1;
    repeat(5) @(posedge pclk); // Wait after reset

    sha256_test(1); // No input argument
    repeat(200) @(posedge pclk);
    sha256_test(0); // No input argument
  end
  always @(posedge pclk) random_i <= $random % 4;
endmodule