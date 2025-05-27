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

  typedef enum logic [1:0] {IDLE, ADDR, DATA} state_t;
  state_t state;

  logic [ADDR_WIDTH-1:0] addr_reg;
  logic [2:0]            size_reg, burst_reg;
  logic                  write_reg;
  logic [7:0]            beats_rem; // Remaining beats
  logic [ADDR_WIDTH-1:0] next_addr;
  logic                  addr_phase_valid;
  logic                  data_phase_active;

  wire transfer_req = htrans[1] && hsel;

  logic [7:0] burst_len;
  always_comb begin
    unique case (hburst)
      3'b000: burst_len = 8'd1;
      3'b001: burst_len = 8'd255;
      3'b010, 3'b011: burst_len = 8'd4;
      3'b100, 3'b101: burst_len = 8'd8;
      3'b110, 3'b111: burst_len = 8'd16;
      default: burst_len = 8'd1;
    endcase
  end

always_comb begin
  logic [ADDR_WIDTH-1:0] increment;
  logic [ADDR_WIDTH-1:0] wrap_mask;
  logic [ADDR_WIDTH-1:0] boundary_mask;
  increment = 1 << size_reg;
  case (burst_reg)
    3'b000: next_addr = addr_reg; // SINGLE 
    3'b001: next_addr = addr_reg + increment; // INCR
    3'b010: begin // WRAP4
      wrap_mask = (increment << 2) - 1;
      boundary_mask = ~wrap_mask;
      next_addr = (addr_reg & boundary_mask) | ((addr_reg + increment) & wrap_mask);
    end
    3'b011: next_addr = addr_reg + increment; // INCR4
    3'b100: begin // WRAP8
      wrap_mask = (increment << 3) - 1;
      boundary_mask = ~wrap_mask;
      next_addr = (addr_reg & boundary_mask) | ((addr_reg + increment) & wrap_mask);
    end
    3'b101: next_addr = addr_reg + increment; // INCR8
    3'b110: begin // WRAP16
      wrap_mask = (increment << 4) - 1;
      boundary_mask = ~wrap_mask;
      next_addr = (addr_reg & boundary_mask) | ((addr_reg + increment) & wrap_mask);
    end
    3'b111: next_addr = addr_reg + increment; // INCR16
    default: next_addr = addr_reg;
  endcase
end

  always_comb begin
    state = IDLE;
    if (!hresetn) state = IDLE;
    else if (transfer_req && hready && !addr_phase_valid && !data_phase_active) state = ADDR;
    else if (addr_phase_valid) state = DATA;
  end

  // Conduit Interface
  assign con_waddr   = (state == ADDR) ? haddr : addr_reg;
  assign con_raddr   = (state == ADDR) ? haddr : addr_reg;
  assign con_wdata   = hwdata;
  assign con_rd_ack  = con_rd;

  // Error Response FSM
  typedef enum logic [1:0] {RESP_OKAY, RESP_WAIT1, RESP_ERROR} resp_state_t;
  resp_state_t resp_state = RESP_OKAY;

  always_ff @(posedge hclk or negedge hresetn) begin
    if (!hresetn)
      resp_state <= RESP_OKAY;
    else begin
      case (resp_state)
        RESP_OKAY:  if (con_slverr)   resp_state <= RESP_WAIT1;
        RESP_WAIT1:                   resp_state <= RESP_ERROR;
        RESP_ERROR:                   resp_state <= RESP_OKAY;
      endcase
    end
  end

  always_comb begin
    hreadyout = 1'b1;
    hresp     = 1'b0;
    case (resp_state)
      RESP_OKAY: begin
        hreadyout = 1'b1;
        hresp     = 1'b0;
      end
      RESP_WAIT1: begin
        hreadyout = 1'b0; // stall cycle
        hresp     = 1'b1; // signal error
      end
      RESP_ERROR: begin
        hreadyout = 1'b1;
        hresp     = 1'b1;
      end
    endcase
  end

  // === Data/Write/Read Enable ===
  always_comb begin
    con_wr = (state == DATA) && write_reg && (resp_state == RESP_OKAY);
    con_rd = (state != IDLE) && !write_reg && (resp_state == RESP_OKAY);
  end
  
 logic [DATA_WIDTH-1:0] hrdata_reg;

  always_ff @(posedge hclk or negedge hresetn) begin
    if (!hresetn)
      hrdata_reg <= '0;
    else if (!write_reg && con_rd_ack && (state == DATA))
      hrdata_reg <= con_rdata;
  end
  
  assign hrdata = (!write_reg && con_rd_ack && (state == DATA)) ? con_rdata : hrdata_reg;

always_ff @(posedge hclk or negedge hresetn) begin
  if (!hresetn) begin
    addr_reg          <= '0;
    size_reg          <= 3'b010;
    burst_reg         <= 3'b000;
    write_reg         <= 1'b0;
    beats_rem         <= 8'd0;
    addr_phase_valid  <= 1'b0;
    data_phase_active <= 1'b0;
  end else begin
    if (state == ADDR && hsel) begin
      addr_reg         <= haddr;
      size_reg         <= hsize;
      burst_reg        <= hburst;
      write_reg        <= hwrite;
      beats_rem        <= burst_len;
      addr_phase_valid <= 1'b1;
      data_phase_active <= 1'b1;
    end else if (state == DATA && ((write_reg && con_wr_ack) || (!write_reg && con_rd_ack))) begin
      if (beats_rem != 8'd1) begin
        beats_rem        <= beats_rem - 1;
        addr_reg         <= next_addr;
        addr_phase_valid <= 1'b1;
      end else begin
        addr_phase_valid  <= 1'b0;
        data_phase_active <= 1'b0;
      end
    end else if (state == IDLE) begin
      addr_phase_valid  <= 1'b0;
      data_phase_active <= 1'b0;
    end
  end
end

endmodule
