`timescale 1ns/1ps
`include "../../sources_1/new/defines.v"

module hmac_apb_wrapper_tb;

    // Parameters
    parameter int D_WIDTH = `WORD_SIZE;
    parameter int A_WIDTH = 12;

    // APB Signals
    logic                 pclk;
    logic                 presetn;
    logic [A_WIDTH-1:0]   paddr;
    logic                 psel;
    logic                 penable;
    logic                 pwrite;
    logic [D_WIDTH-1:0]   pwdata;
    logic [D_WIDTH/8-1:0] pstrb;
    logic                 pready;
    logic [D_WIDTH-1:0]   prdata;
    logic                 pslverr;

    // Instantiate the HMAC APB Wrapper
    hmac_apb_wrapper dut (
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
        .dma_wr_req_o(),
        .dma_rd_req_o(),
        .aux_key_i(32'h0),
        .irq_o(),
        .random_i(2'b00)
    );

    // Clock Generation
    initial begin
        pclk = 0;
        forever #5 pclk = ~pclk; // 100 MHz clock
    end

    // Testbench Logic
    initial begin
        // Initialize signals
        presetn = 0;
        psel = 0;
        penable = 0;
        pwrite = 0;
        paddr = 0;
        pwdata = 0;
        pstrb = '1;
        #20;
        presetn = 1;
        #20;

        // Test Sequence
        $display("Starting HMAC operation...");

        // 1. Write 1024-bit key (16 words)
        $display("Writing key...");
        for (int i = 0; i < 16; i++) begin
            apb_write(12'h140, 64'h0123456789abcdef + i*16);
            @(posedge pclk);
        end

        // 2. Start HMAC operation
        $display("Starting HMAC...");
        apb_write(12'h144, 32'hDEADBEEF);
        apb_write(12'h020, 32'h1); // INIT=1

        // 3. Write data packets
        $display("Writing data...");
        apb_write(12'h144, 32'hDEADBEEF);
        apb_write(12'h144, 32'hCAFEBABE);
        apb_write(12'h144, 32'h12345678);

        // 4. Finalize
        $display("Finalizing...");
        apb_write(12'h020, 32'h2); // LAST=1

        // 5. Wait for completion
        $display("Waiting for completion...");
        wait_for_status(1);

        // 6. Read hash
        $display("Reading hash...");
        for (int i = 0; i < 8; i++) begin
            logic [D_WIDTH-1:0] rd_data;
            apb_read(12'h100 + i*4, rd_data);
            $display("Hash word %0d: %h", i, rd_data);
        end

        $display("Test complete");
        $finish;
    end

    // APB Write Task
    task apb_write(input logic [A_WIDTH-1:0] addr, input logic [D_WIDTH-1:0] data);
        @(posedge pclk);
        psel = 1;
        pwrite = 1;
        paddr = addr;
        pwdata = data;
        @(posedge pclk);
        penable = 1;
        @(posedge pclk);
        wait(pready);
        psel = 0;
        penable = 0;
        $display("APB Write: Addr=%h Data=%h", addr, data);
    endtask

    // APB Read Task
    task apb_read(input logic [A_WIDTH-1:0] addr, output logic [D_WIDTH-1:0] data);
        @(posedge pclk);
        psel = 1;
        pwrite = 0;
        paddr = addr;
        @(posedge pclk);
        penable = 1;
        @(posedge pclk);
        wait(pready);
        data = prdata;
        psel = 0;
        penable = 0;
        $display("APB Read: Addr=%h Data=%h", addr, data);
    endtask

    // Status Wait Task
    task wait_for_status(input bit expected);
        logic [D_WIDTH-1:0] status;
        do begin
            apb_read(12'h030, status);
            #20;
        end while (status[0] != expected);
    endtask
endmodule
