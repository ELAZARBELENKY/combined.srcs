`include "defines.v"
module hmac_apb_wrapper #(
    parameter int D_WIDTH = `WORD_SIZE,
    parameter int A_WIDTH = 12,
    parameter int FIFO_SIZE = 1,
    parameter bit DMA_EN = 0
) (
    // APB Interface
    input  logic                 pclk,
    input  logic                 presetn,
    input  logic [A_WIDTH-1:0]   paddr,
    input  logic                 psel,
    input  logic                 penable,
    input  logic                 pwrite,
    input  logic [D_WIDTH-1:0]   pwdata,
    input  logic [D_WIDTH/8-1:0] pstrb,
    output logic                 pready,
    output logic [D_WIDTH-1:0]   prdata,
    output logic                 pslverr,
    
    // DMA Interface
    output logic                 dma_wr_req_o,
    output logic                 dma_rd_req_o,
    
    // Additional Signals
    input  logic [D_WIDTH-1:0]   aux_key_i,
    output logic                 irq_o,
    input  logic [1:0]           random_i
);

    // Conduit Interface
    logic                 con_wr;
    logic                 con_wr_ack;
    logic                 con_rd;
    logic                 con_rd_ack;
    logic [A_WIDTH-1:0]   con_waddr;
    logic [A_WIDTH-1:0]   con_raddr;
    logic [D_WIDTH-1:0]   con_wdata;
    logic [D_WIDTH/8-1:0] con_wbyte_enable;
    logic [D_WIDTH/8-1:0] con_rbyte_enable;
    logic [D_WIDTH-1:0]   con_rdata;
    logic                 con_read_valid;
    logic                 con_slv_error;

    // HMAC Interface Signals
    logic                 hmac_start_i;
    logic                 hmac_abort_i;
    logic                 hmac_last_i;
    logic                 hmac_data_valid_i;
    logic [63:0]          hmac_data_i;
    logic [3:0]           hmac_opcode_i;
    logic [63:0]          hmac_key_i;
    logic                 hmac_key_valid_i;
    logic                 hmac_key_ready_o;
    logic [63:0]          hmac_hash_o[7:0];
    logic                 hmac_ready_o;
    logic                 hmac_core_ready_o;
    logic                 hmac_done_o;
    logic                 hmac_fault_inj_det_o;

    // Internal registers
    logic [63:0]          key_buffer[7:0]; // 512-bit key buffer
    logic [2:0]           key_index;
    logic                 key_loaded;
    logic                 operation_active;
    
    // FIFO signals
    logic [D_WIDTH-1:0]   fifo [FIFO_SIZE];
    logic [$clog2(FIFO_SIZE):0] fifo_count;
    logic                 fifo_full, fifo_empty;
    
    // Interrupt signals
    logic                 hash_avail_irq;
    logic                 fault_irq;
    logic                 key_unlock_irq;
    logic                 data_err_irq;
    
    // Configuration registers
    logic [31:0]          cfg_reg;
    logic [31:0]          ie_reg; // Interrupt Enable

    // Instantiate APB Slave Adapter
    apb_slave_adapter #(
        .D_WIDTH(D_WIDTH),
        .A_WIDTH(A_WIDTH)
    ) apb_adapter (
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
        .con_wr(con_wr),
        .con_wr_ack(con_wr_ack),
        .con_rd(con_rd),
        .con_rd_ack(con_rd_ack),
        .con_waddr(con_waddr),
        .con_raddr(con_raddr),
        .con_wdata(con_wdata),
        .con_wbyte_enable(con_wbyte_enable),
        .con_rbyte_enable(con_rbyte_enable),
        .con_rdata(con_rdata),
        .con_read_valid(con_read_valid),
        .con_slv_error(con_slv_error)
    );

    // FIFO Control
    assign fifo_full = (fifo_count == FIFO_SIZE);
    assign fifo_empty = (fifo_count == 0);
    
    // DMA Control
    generate
        if (DMA_EN) begin
            assign dma_wr_req_o = (fifo_count < (FIFO_SIZE/2)); // Request when half empty
            assign dma_rd_req_o = hmac_done_o; // Request read when hash available
        end else begin
            assign dma_wr_req_o = 0;
            assign dma_rd_req_o = 0;
        end
    endgenerate
    
    // Interrupt Control
    assign irq_o = (hash_avail_irq & ie_reg[0]) | 
                  (fault_irq & ie_reg[4]) |
                  (key_unlock_irq & ie_reg[5]) |
                  (data_err_irq & ie_reg[2]);

    // Conduit Interface Handling
    assign con_wr_ack = 1'b1; // Immediate acknowledge
//    assign con_rd_ack = 1'b1; // Immediate acknowledge
    assign con_slv_error = 1'b0; // No slave errors
    
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            // Reset all registers
            hmac_start_i <= 0;
            hmac_abort_i <= 0;
            hmac_last_i <= 0;
            hmac_data_valid_i <= 0;
            hmac_opcode_i <= 0;
            hmac_key_valid_i <= 0;
            key_index <= 0;
            key_loaded <= 0;
            operation_active <= 0;
            fifo_count <= 0;
            cfg_reg <= 0;
            ie_reg <= 0;
            hash_avail_irq <= 0;
            fault_irq <= 0;
            key_unlock_irq <= 0;
            data_err_irq <= 0;
        end
        else begin
            // Handle conduit writes
            if (con_wr) begin
                case (con_waddr)
                    // CFG Register
                    12'h010: cfg_reg <= con_wdata;
                    
                    // CTL Register
                    12'h020: begin
                        hmac_abort_i <= con_wdata[2]; // ABORT
                        hmac_last_i <= con_wdata[1];   // LAST
                        if (con_wdata[0]) begin       // INIT
                            hmac_start_i <= 1;
                            operation_active <= 1;
                        end
                    end
                    
                    // IE Register
                    12'h040: ie_reg <= con_wdata;
                    
                    // Key Input (DIN0)
                    12'h140: begin
                        if (!key_loaded && key_index < 8) begin
                            key_buffer[key_index] <= con_wdata;
                            key_index <= key_index + 1;
                            if (key_index == 7) begin
                                key_loaded <= 1;
                                key_unlock_irq <= 1;
                            end
                        end
                    end
                    
                    // Data Input (DIN0)
                    12'h144: begin
                        if (!fifo_full) begin
                            fifo[fifo_count] <= con_wdata;
                            fifo_count <= fifo_count + 1;
                        end else begin
                            data_err_irq <= 1;
                        end
                    end
                endcase
            end
            
            // Handle data processing
            if (operation_active && !fifo_empty && hmac_ready_o) begin
                hmac_data_i <= fifo[0];
                hmac_data_valid_i <= 1;
                // Shift FIFO
                for (int i = 0; i < FIFO_SIZE-1; i++) begin
                    fifo[i] <= fifo[i+1];
                end
                fifo_count <= fifo_count - 1;
            end else begin
                hmac_data_valid_i <= 0;
            end
            
            // Handle HMAC completion
            if (hmac_done_o) begin
                operation_active <= 0;
                hash_avail_irq <= 1;
                if (hmac_fault_inj_det_o) begin
                    fault_irq <= 1;
                end
            end
            
            // Clear interrupts on read
            if (con_rd) begin
                case (con_raddr)
                    12'h030: begin // Status register read clears interrupts
                        hash_avail_irq <= 0;
                        fault_irq <= 0;
                        key_unlock_irq <= 0;
                        data_err_irq <= 0;
                    end
                endcase
            end
        end
    end

    // Read logic
    always_comb begin
        con_read_valid = 1'b1; // Always valid
        case (con_raddr)
            // ID Register
            12'h000: con_rdata = 32'hF1aa0001; // Example ID
            
            // CFG Register
            12'h010: con_rdata = cfg_reg;
            
            // Status Register (STS)
            12'h030: con_rdata = {26'b0, hmac_fault_inj_det_o, hmac_done_o, 
                              operation_active, data_err_irq, 
                              hmac_core_ready_o, hash_avail_irq};
            
            // IE Register
            12'h040: con_rdata = ie_reg;
            
            // Hash Output (HASH)
            12'h100: con_rdata = hmac_hash_o[0][31:0];
            12'h104: con_rdata = hmac_hash_o[1][31:0];
            // ... other hash output registers
            
            default: con_rdata = '0;
        endcase
    end

    // Instantiate HMAC core
    lw_hmac hmac_inst (
        .clk_i(pclk),
        .aresetn_i(presetn),
        .start_i(hmac_start_i),
        .abort_i(hmac_abort_i),
        .last_i(hmac_last_i),
        .data_valid_i(hmac_data_valid_i),
        .data_i(hmac_data_i),
        .random_i(random_i),
        .opcode_i(4'h8), // HMAC-256
        .key_i(key_loaded ? key_buffer[key_index] : 64'h0),
        .key_valid_i(key_loaded && (key_index < 8)),
        .key_ready_o(hmac_key_ready_o),
        .hash_o(hmac_hash_o),
        .ready_o(hmac_ready_o),
        .core_ready_o(hmac_core_ready_o),
        .done_o(hmac_done_o),
        .fault_inj_det_o(hmac_fault_inj_det_o)
    );
endmodule