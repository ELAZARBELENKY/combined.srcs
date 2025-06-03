module ahb_slave_adapter #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 12
) (
    input  logic                   hclk,
    input  logic                   hresetn,
    input  logic                   hsel,

    input  logic [ADDR_WIDTH-1:0]  haddr,
    input  logic [2:0]             hburst,
    input  logic                   hready,
    input  logic [2:0]             hsize,
    input  logic [1:0]             htrans,
    input  logic [DATA_WIDTH-1:0]  hwdata,
    input  logic                   hwrite,

    output logic [DATA_WIDTH-1:0]  hrdata,
    output logic                   hreadyout,
    output logic                   hresp,

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

  // Current transfer registers (data phase)
  logic [ADDR_WIDTH-1:0] current_addr;
  logic [2:0]            current_size;
  logic [2:0]            current_burst;
  logic                  current_write;
  logic [7:0]            current_beats_remaining;
  logic                  current_active;

//  // Pending transfer registers (address phase)
//  logic [ADDR_WIDTH-1:0] pending_addr;
//  logic [2:0]            pending_size;
//  logic [2:0]            pending_burst;
//  logic                  pending_write;
//  logic                  pending_valid;

  logic [ADDR_WIDTH-1:0] next_addr;

  // Burst length calculation
  logic [7:0] burst_len;
  always_comb begin
    unique case (hburst)
      3'b000: burst_len = 8'd1;          // SINGLE
      3'b001: burst_len = 8'd255;        // INCR
      3'b010, 3'b011: burst_len = 8'd4;  // WRAP4, INCR4
      3'b100, 3'b101: burst_len = 8'd8;  // WRAP8, INCR8
      3'b110, 3'b111: burst_len = 8'd16; // WRAP16, INCR16
      default: burst_len = 8'd1;         // Default to SINGLE
    endcase
  end

  // Next address calculation for bursts
  always_comb begin
    logic [ADDR_WIDTH-1:0] increment;
    logic [ADDR_WIDTH-1:0] wrap_mask;
    logic [ADDR_WIDTH-1:0] boundary_mask;
    increment = 1 << current_size;
    case (current_burst)
      3'b000: next_addr = current_addr; // SINGLE
      3'b001: next_addr = current_addr + increment; // INCR
      3'b010: begin // WRAP4
        wrap_mask = (increment << 2) - 1;
        boundary_mask = ~wrap_mask;
        next_addr = (current_addr & boundary_mask) | ((current_addr + increment) & wrap_mask);
      end
      3'b011: next_addr = current_addr + increment; // INCR4
      3'b100: begin // WRAP8
        wrap_mask = (increment << 3) - 1;
        boundary_mask = ~wrap_mask;
        next_addr = (current_addr & boundary_mask) | ((current_addr + increment) & wrap_mask);
      end
      3'b101: next_addr = current_addr + increment; // INCR8
      3'b110: begin // WRAP16
        wrap_mask = (increment << 4) - 1;
        boundary_mask = ~wrap_mask;
        next_addr = (current_addr & boundary_mask) | ((current_addr + increment) & wrap_mask);
      end
      3'b111: next_addr = current_addr + increment; // INCR16
      default: next_addr = current_addr;
    endcase
  end

  logic new_transfer;

  // Process data phase with current transfer
  always_ff @(posedge hclk or negedge hresetn) begin
    if (!hresetn) begin
      current_active          <= 1'b0;
      current_beats_remaining <= 8'd0;
      current_addr            <= '0;
      current_size            <= '0;
      current_burst           <= '0;
      current_write           <= 1'b0;
    end else begin
      if (current_beats_remaining > 1) begin
        current_addr <= next_addr;
        current_beats_remaining <= current_beats_remaining - 1;
      end else if (new_transfer) begin
        // Start transfer when idle
        current_addr            <= haddr;
        current_size            <= hsize;
        current_burst           <= hburst;
        current_write           <= hwrite;
        current_active          <= 1'b1;
        current_beats_remaining <= burst_len;
      end else         
        current_active <= 1'b0;
    end
  end
  
  assign new_transfer = htrans[1] && hsel && hreadyout;

  // Conduit signals - immediate response to AHB bus OR ongoing burst
  assign con_wr = (current_active && current_write);
  assign con_rd = (current_active && !current_write);
  
  // Address - immediate from AHB bus for new transfers, from current for bursts
  assign con_waddr = current_addr;
  assign con_raddr = current_addr;
  assign con_wdata = hwdata;
  assign con_rd_ack = con_rd;

  // HRDATA: Direct from conduit (assuming valid when con_rd_ack)
  assign hrdata = con_rdata;

  // Error Response FSM
  typedef enum logic [1:0] {RESP_OKAY, RESP_WAIT, RESP_ERROR} resp_state_t;
  resp_state_t resp_state;

  always_ff @(posedge hclk or negedge hresetn) begin
    if (!hresetn) begin
      resp_state <= RESP_OKAY;
    end else begin
      case (resp_state)
        RESP_OKAY:  if (con_slverr) resp_state <= RESP_ERROR; // Immediate error response
        RESP_WAIT:  resp_state <= RESP_ERROR;
        RESP_ERROR: resp_state <= RESP_OKAY;
      endcase
    end
  end

  always_comb begin
    hreadyout = 1'b1;
    hresp     = 1'b0;
    case (resp_state)
      RESP_OKAY: begin
        hreadyout = !con_slverr;
        hresp     = con_slverr;
      end
      RESP_WAIT: begin
        hreadyout = 0;
        hresp     = 1;
      end
      RESP_ERROR: begin
        hreadyout = 1'b1;
        hresp     = 1'b1;
      end
    endcase
  end

endmodule