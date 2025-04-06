module apb_top_tb;
`include "../../sources_1/new/defines.v"
  // Parameters
  parameter FIQSHA_BUS_DATA_WIDTH = 32;
  parameter ADDR_WIDTH = 12;
  parameter HASH_WIDTH = (FIQSHA_BUS_DATA_WIDTH == 32) ? 256 : 512;

  // Signals
  reg pclk = 0;
  reg presetn;
  reg psel;
  reg penable;
  reg pwrite;
  reg [ADDR_WIDTH-1:0] paddr;
  reg [FIQSHA_BUS_DATA_WIDTH-1:0] pwdata;
  wire pready;
  wire [FIQSHA_BUS_DATA_WIDTH-1:0] prdata;
  wire pslverr;
  wire irq_o;
  reg [255:0] aux_key_i;
  reg [1:0] random_i;
  wire dma_wr_req_o;
  wire dma_rd_req_o;

  // Testbench Execution
  reg [HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH - 1:0][FIQSHA_BUS_DATA_WIDTH - 1:0] hash_result;

  // Instantiate
  lw_sha_apb_top dut (
    .pclk(pclk),
    .presetn(presetn),
    .paddr(paddr),
    .psel(psel),
    .penable(penable),
    .pwrite(pwrite),
    .pwdata(pwdata),
    .pready(pready),
    .prdata(prdata),
    .pslverr(pslverr),
    .irq_o(irq_o),
    .aux_key_i(aux_key_i),
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
    @(posedge pclk);
    presetn = 1;
  end

  // APB Write Task (Cycle-Accurate)
  task apb_write;
    input [ADDR_WIDTH - 1:0] addr;
    input [FIQSHA_BUS_DATA_WIDTH - 1:0] wdata;
    begin
      psel = 1;           // Select the slave
      paddr = addr;       // Set address
      pwdata = wdata;       // Set write data
      pwrite = 1;         // Write transaction
      penable = 0;        // Setup phase - penable LOW
      @(posedge pclk);     // End of Setup phase
      if (addr == 'h140 && ~pready) wait (pready==1); // Wait for slave to be ready

      penable = 1;        // Enable phase - penable HIGH
      @(posedge pclk);     // Slave samples data

      penable = 0;        // End of Enable phase
      psel = 0;         // Deselect the slave
//      @(posedge pclk);     // Wait for pready
    end
  endtask

// APB Read Task (Cycle-Accurate)
task apb_read;
  input [ADDR_WIDTH - 1:0] addr;
  output reg [FIQSHA_BUS_DATA_WIDTH - 1:0] rdata;
  begin
    wait(pready == 1);   // Wait for slave to be ready
    psel = 1;            // Select slave
    paddr = addr;        // Set address
    pwrite = 0;          // Read transaction
    penable = 0;         // Setup phase
    @(posedge pclk);     // End of Setup phase

    penable = 1;         // Enable phase
    @(posedge pclk);     // Slave samples address and starts data transfer
    
    wait(pready == 1);   // Wait for slave ready (data available)
    rdata = prdata;      // Capture read data

    // Clear signals
    psel = 0;            // Deselect slave
    penable = 0;         // Disable transaction
    paddr = '0;          // Clear address (optional, for safety)
  end
endtask

  // SHA-256 Test Case (Precise, with Padding)
  task automatic sha256_test;
  
    //input [FIQSHA_BUS_DATA_WIDTH - 1:0] test_data;
    begin
      // Padded data for "abc" (512 bits = 64 bytes)
//      localparam string input_str = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstuabcdefghigklmnopqrstuvwxyz";
      localparam string input_str = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu";
//      localparam string input_str = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
//      localparam string input_str = "abc";
      localparam length = input_str.len()*8;
      localparam num = length >= `WORD_SIZE*14 ?
        16<<($clog2(length+`WORD_SIZE*2+1)-($clog2(`WORD_SIZE)+4)):16;
      reg [num*`WORD_SIZE-1:0] padded_data = 0;

      logic [length-1:0] hex_value;
      // Converting each character to its hexadecimal value
      for (int i = 0; i < length; i++) begin
          hex_value[(length-1 - i * 8) -: 8] = input_str[i];
      end
      padded_data[num*`WORD_SIZE-1-:length+1] = {hex_value,1'b1};
      padded_data[11:0] = length;
      $display("%h", padded_data);
      $display("%d", num);
//      // 1. Reset the core
//      apb_write('h10, 32'h1);
//      repeat(2) @(posedge pclk);
//      apb_write('h10, 32'h0);
//      repeat(2) @(posedge pclk);
  
      // 2. Configure for SHA-256
      apb_write('h10, 32'h0); // OPCODE = 0
//      apb_write('h10, 32'h0);
  
//      wait(pready == 1);
      apb_write('h20, 32'h1);  // CTL.INIT = 1
//      apb_write('h20, 32'h0);
      
//      wait(pready == 1);
//      apb_write('h20, 32'h1);  // CTL.LAST = 1
//      apb_write('h20, 32'h0);
      
         // 3. Send Data (Padded - 512 bits)
      for (int i = 0; i < num; i++) begin
          apb_write('h140, padded_data[(num*`WORD_SIZE-1 - (i * `WORD_SIZE)) -: `WORD_SIZE]); // Write data segment
          if (i == num/2) apb_write('h20, 32'h2);
      end

      // 4. Wait for result (CRITICAL: Adjust!)
//      repeat(50) @(posedge pclk);
 
      // 5. Read the hash result
      for (int i = 0; i < HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH; i++) begin
        apb_read('h100 + (i * (FIQSHA_BUS_DATA_WIDTH / 8)), hash_result[i]);
        @(posedge pclk); // Add a clock cycle after each read
      end
  
      $display("SHA-256 Test Result:");
      $display("Input Data: %h", padded_data);
      $display("Hash Result: %h", hash_result);
  
    end
  endtask
  initial begin
    // Initialize ALL signals!
    pclk = 0;
    presetn = 0;
    psel = 0;
    penable = 0;
    pwrite = 0;
    paddr = 0;
    pwdata = 0;
    aux_key_i = 0;
    random_i = 0;

    // Run tests
    presetn = 0;
    repeat(2) @(posedge pclk); // Clock some cycles
    presetn = 1;
    repeat(5) @(posedge pclk); // Wait after reset

    sha256_test(); // No input argument
    repeat(200) @(posedge pclk);

//    $finish;
  end

endmodule