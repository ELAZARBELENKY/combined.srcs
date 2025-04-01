module apb_top_tb;

  // Parameters
  parameter FIQSHA_BUS_DATA_WIDTH = 32;
  parameter ADDR_WIDTH = 12;
  parameter HASH_WIDTH = (FIQSHA_BUS_DATA_WIDTH == 32) ? 256 : 512;

  // Signals
  reg pclk;
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
  parameter CLK_PERIOD = 10;
  initial begin
    pclk = 0;
    forever #(CLK_PERIOD / 2) pclk = ~pclk;
  end

  // Reset
  initial begin
    presetn = 0;
    repeat(2) @(posedge pclk);
    presetn = 1;
    repeat(5) @(posedge pclk); // Give time after reset
  end

  // APB Write Task (Cycle-Accurate)
  task apb_write;
    input [ADDR_WIDTH - 1:0] addr;
    input [FIQSHA_BUS_DATA_WIDTH - 1:0] wdata;
    begin
      psel = 1;         // Select the slave
      paddr = addr;       // Set address
      pwdata = wdata;       // Set write data
      pwrite = 1;         // Write transaction
      penable = 0;        // Setup phase - penable LOW
      @(posedge pclk);     // End of Setup phase

      penable = 1;        // Enable phase - penable HIGH
      @(posedge pclk);     // Slave samples data

      penable = 0;        // End of Enable phase
      psel = 0;         // Deselect the slave
      wait(pready == 1); // Wait for slave to be ready
      @(posedge pclk);     // Wait for pready
    end
  endtask

  // APB Read Task (Cycle-Accurate)
  task apb_read;
    input [ADDR_WIDTH - 1:0] addr;
    output reg [FIQSHA_BUS_DATA_WIDTH - 1:0] rdata;
    begin
      psel = 1;         // Select slave
      paddr = addr;       // Set address
      pwrite = 0;         // Read transaction
      penable = 0;        // Setup phase
      @(posedge pclk);     // End of Setup phase

      penable = 1;        // Enable phase
      @(posedge pclk);     // Slave samples address
      wait(pready == 1); // Wait for slave ready
      @(posedge pclk);     // Data available

      rdata = prdata;       // Read data
      psel = 0;         // Deselect
      penable = 0;
    end
  endtask

  // SHA-256 Test Case (Precise, with Padding)
  task automatic sha256_test;
    //input [FIQSHA_BUS_DATA_WIDTH - 1:0] test_data;
    begin
      // Padded data for "abc" (512 bits = 64 bytes)
      reg [511:0] padded_data = 512'h61626380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018;
  
      // 1. Reset the core
      apb_write('h10, 32'h1);
      repeat(10) @(posedge pclk);
      apb_write('h10, 32'h0);
      repeat(10) @(posedge pclk);
  
      // 2. Configure for SHA-256
      apb_write('h10, 32'h0); // OPCODE = 0
      apb_write('h10, 32'h0);
  
      // 3. Send Data (Padded - 512 bits)
      apb_write('h140, padded_data[31:0]);  // DIN0 (LSB)
      wait(pready == 1);
      apb_write('h144, padded_data[63:32]); // DIN1
      wait(pready == 1);
      apb_write('h148, padded_data[95:64]); // DIN2
      wait(pready == 1);
      apb_write('h14C, padded_data[127:96]); // DIN3
      wait(pready == 1);
      apb_write('h150, padded_data[159:128]); // DIN4
      wait(pready == 1);
      apb_write('h154, padded_data[191:160]); // DIN5
      wait(pready == 1);
      apb_write('h158, padded_data[223:192]); // DIN6
      wait(pready == 1);
      apb_write('h15C, padded_data[255:224]); // DIN7
      wait(pready == 1);
      apb_write('h160, padded_data[287:256]); // DIN8
      wait(pready == 1);
      apb_write('h164, padded_data[319:288]); // DIN9
      wait(pready == 1);
      apb_write('h168, padded_data[351:320]); // DIN10
      wait(pready == 1);
      apb_write('h16C, padded_data[383:352]); // DIN11
      wait(pready == 1);
      apb_write('h170, padded_data[415:384]); // DIN12
      wait(pready == 1);
      apb_write('h174, padded_data[447:416]); // DIN13
      wait(pready == 1);
      apb_write('h178, padded_data[479:448]); // DIN14
      wait(pready == 1);
      apb_write('h17C, padded_data[511:480]); // DIN15 (MSB)
  
      wait(pready == 1);
      apb_write('h20, 32'h1);  // CTL.INIT = 1
      apb_write('h20, 32'h0);
  
      wait(pready == 1);
      apb_write('h20, 32'h1);  // CTL.LAST = 1
      apb_write('h20, 32'h0);
  
      // 4. Wait for result (CRITICAL: Adjust!)
      repeat(200) @(posedge pclk);
  
      // 5. Read the hash result
      for (int i = 0; i < HASH_WIDTH / FIQSHA_BUS_DATA_WIDTH; i++) begin
        apb_read('h100 + (i * (FIQSHA_BUS_DATA_WIDTH / 8)), hash_result[i]);
        @(posedge pclk); // Add a clock cycle after each read
      end
  
      $display("SHA-256 Test Result:");
      $display("Input Data: %h", padded_data);
      $display("Hash Result: %p", hash_result);
  
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
    repeat(2) @(posedge pclk); // Clock some cycles
    presetn = 1;
    repeat(5) @(posedge pclk); // Wait after reset

    sha256_test(); // No input argument
    repeat(200) @(posedge pclk);

    $finish;
  end

endmodule