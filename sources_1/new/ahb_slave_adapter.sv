/*
 *  AHB full slave adapter with burst support
 *  Simplified and corrected:
 *  - Proper address/data phases
 *  - Fixed state machine
 *  - Nonblocking assignments in ff block
 *  - Eliminated unused grants
 */
module ahb_slave_adapter #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
) (
    input  logic                   hclk,
    input  logic                   hresetn,
    
    // AHB-lite interface
    input  logic [ADDR_WIDTH-1:0]  haddr,
    input  logic [2:0]             hburst,
    input  logic                   hready,
    input  logic [2:0]             hsize,
    input  logic [1:0]             htrans,
    input  logic [DATA_WIDTH-1:0]  hwdata,
    input  logic                   hwrite,

    output logic [DATA_WIDTH-1:0]  hrdata,
    output logic                   hreadyout,
    output logic [1:0]             hresp,

    // Conduit interface
    output logic                   con_wr,
    output logic                   con_rd,
    output logic [ADDR_WIDTH-1:0]  con_waddr,
    output logic [ADDR_WIDTH-1:0]  con_raddr,
    output logic [DATA_WIDTH-1:0]  con_wdata,
    input  logic [DATA_WIDTH-1:0]  con_rdata,
    output logic                   con_rd_ack,
    input  logic                   con_wr_ack,
    input  logic                   con_slverr
);

  // State machine
  typedef enum logic [1:0] {IDLE, ADDR, DATA} state_t;
  state_t state, next_state;

  // Transaction registers
  logic [ADDR_WIDTH-1:0]      addr_reg;
  logic [2:0]                 size_reg;
  logic [2:0]                 burst_reg;
  logic                       write_reg;
  logic [7:0]                 beats_rem;

  // Decode valid transfer
  wire transfer_req = (htrans == 2'b10) || (htrans == 2'b11);

  // Burst length
  logic [7:0] burst_len;
  always_comb begin
    unique case (hburst)
      3'b000: burst_len = 8'd1;
      3'b001: burst_len = 8'd0; // INCR, unspecified
      3'b010, 3'b011: burst_len = 8'd4;
      3'b100, 3'b101: burst_len = 8'd8;
      3'b110, 3'b111: burst_len = 8'd16;
      default: burst_len = 8'd1;
    endcase
  end

  // Next address calculation for incrementing only
  logic [ADDR_WIDTH-1:0] next_addr;
  always_comb begin
    next_addr = addr_reg;
    if (burst_reg != 3'b000) begin
      case (size_reg)
        3'b000: next_addr = addr_reg + 1;
        3'b001: next_addr = addr_reg + 2;
        default: next_addr = addr_reg + 4;
      endcase
    end
  end

  // Conduit outputs
  assign con_waddr  = addr_reg;
  assign con_raddr  = addr_reg;
  assign con_wdata  = hwdata;

  // Conduit handshake
  assign con_wr      = (state == DATA) && write_reg && hready;
  assign con_rd      = (state == DATA) && !write_reg && hready;
  assign con_rd_ack  = con_rd;

  // Default AHB
  always_comb begin
    next_state = state;
    hreadyout  = 1'b1;
    hresp      = 2'b00;

    case (state)
      IDLE: begin
        if (transfer_req && hready) begin
          next_state = ADDR;
          hreadyout  = 1'b1;
        end
      end
      ADDR: begin
        // capture transaction
        next_state = DATA;
      end
      DATA: begin
        // wait for conduit ack
        if (write_reg && !con_wr_ack) begin
          hreadyout = 1'b0;
        end
        if ((!write_reg && con_rd_ack) || (write_reg && con_wr_ack)) begin
          // transferred one beat
          if (beats_rem > 1) begin
            next_state = ADDR;
          end else begin
            next_state = IDLE;
          end
        end
      end
    endcase
  end

  // Sequential
  always_ff @(posedge hclk or negedge hresetn) begin
    if (!hresetn) begin
      state       <= IDLE;
      addr_reg    <= '0;
      size_reg    <= 3'b010;
      burst_reg   <= 3'b000;
      write_reg   <= 1'b0;
      beats_rem   <= 8'd0;
      hrdata      <= '0;
    end else begin
      state <= next_state;
      if (state == ADDR && transfer_req && hready) begin
        addr_reg   <= haddr;
        size_reg   <= hsize;
        burst_reg  <= hburst;
        write_reg  <= hwrite;
        // init beats
        if (hburst == 3'b001)
          beats_rem <= 8'hFF;
        else
          beats_rem <= burst_len;
      end
      if (state == DATA && hready) begin
        // increment/decrement
        if ((write_reg && con_wr_ack) || (!write_reg && con_rd_ack)) begin
          beats_rem <= beats_rem - 8'd1;
          addr_reg  <= next_addr;
        end
        // read data
        if (!write_reg && con_rd_ack) begin
          hrdata <= con_rdata;
        end
      end
    end
  end

endmodule
