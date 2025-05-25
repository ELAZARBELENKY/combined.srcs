/*
 * AHB full slave adapter with burst support and combinational conduit interface
 * - Address and data phases respected
 * - Burst support with address increment
 * - Conduit interface is combinational (immediate reaction)
 * - State machine is now combinational
 */
module ahb_slave_adapter #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 12
) (
    input  logic                   hclk,
    input  logic                   hresetn,

    // AHB interface
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

    // Conduit interface (combinational)
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

  // === STATE MACHINE (now combinational) ===
  typedef enum logic [1:0] {IDLE, ADDR, DATA} state_t;
  state_t state;

  // === TRANSACTION REGISTERS ===
  logic [ADDR_WIDTH-1:0] addr_reg;
  logic [2:0]            size_reg, burst_reg;
  logic                  write_reg;
  logic [7:0]            beats_rem;
  logic [ADDR_WIDTH-1:0] next_addr;
  logic                  addr_phase_valid;
  logic                  data_phase_active;

  // === TRANSFER DECODE ===
  wire transfer_req = (htrans == 2'b10 || htrans == 2'b11);  // NONSEQ / SEQ

  // === BURST LENGTH DECODE ===
  logic [7:0] burst_len;
  always_comb begin
    unique case (hburst)
      3'b000: burst_len = 8'd1;   // SINGLE
      3'b001: burst_len = 8'd255; // INCR (unspecified length)
      3'b010: burst_len = 8'd4;   // INCR4
      3'b011: burst_len = 8'd4;   // WRAP4
      3'b100: burst_len = 8'd8;   // INCR8
      3'b101: burst_len = 8'd8;   // WRAP8
      3'b110: burst_len = 8'd16;  // INCR16
      3'b111: burst_len = 8'd16;  // WRAP16
      default: burst_len = 8'd1;
    endcase
  end

  // === ADDRESS INCREMENT ===
  always_comb begin
    next_addr = addr_reg;
    if (burst_reg != 3'b000) begin
      case (size_reg)
        3'b000: next_addr = addr_reg + 1;   // Byte
        3'b001: next_addr = addr_reg + 2;   // Halfword
        3'b010: next_addr = addr_reg + 4;   // Word
        3'b011: next_addr = addr_reg + 8;   // Double word
        3'b100: next_addr = addr_reg + 16;  // 16-byte line
        default: next_addr = addr_reg + 4;  // Default to word
      endcase
    end
  end

  // === COMBINATIONAL STATE MACHINE ===
  always_comb begin
    if (!hresetn) begin
      state = IDLE;
    end else begin
      if (transfer_req && hready && !addr_phase_valid && !data_phase_active) begin
        state = ADDR;
      end else if (addr_phase_valid) begin
        state = DATA;
      end else begin
        state = IDLE;
      end
    end
  end

  // === CONDUIT INTERFACE ===
  assign con_waddr   = (state == ADDR) ? haddr : addr_reg;
  assign con_raddr   = (state == ADDR) ? haddr : addr_reg;
  assign con_wdata   = hwdata;
  assign con_rd_ack  = con_rd;
  assign hresp       = con_slverr;

  // === COMBINATIONAL LOGIC ===
  always_comb begin
    con_wr = (state == DATA) && write_reg;
    con_rd = (state == DATA) && !write_reg;
    hreadyout = 1'b1;
    if (state == DATA && write_reg && !con_wr_ack) begin
      hreadyout = 1'b0;
    end
    if (state == DATA && !write_reg && con_rdata !== hrdata) begin
      hreadyout = 1'b0;  // Wait for read data to be stable
    end
  end

  // === SEQUENTIAL LOGIC (registers only) ===
  always_ff @(posedge hclk or negedge hresetn) begin
    if (!hresetn) begin
      addr_reg         <= '0;
      size_reg         <= 3'b010;
      burst_reg        <= 3'b000;
      write_reg        <= 1'b0;
      beats_rem        <= 8'd0;
      hrdata           <= '0;
      addr_phase_valid <= 1'b0;
      data_phase_active <= 1'b0;
    end else begin
      // Address phase capture
      if (state == ADDR) begin
        addr_reg         <= haddr;
        size_reg         <= hsize;
        burst_reg        <= hburst;
        write_reg        <= hwrite;
        beats_rem        <= (hburst == 3'b001) ? 8'hFF : burst_len;
        addr_phase_valid <= 1'b1;
        data_phase_active <= 1'b1;
      end
      
      // Data phase completion
      if (state == DATA && ((write_reg && con_wr_ack) || (!write_reg && con_rd_ack))) begin
        if (!write_reg) begin
          hrdata <= con_rdata;
        end
        
        if (beats_rem > 1) begin
          // Continue burst - prepare for next address phase
          beats_rem        <= beats_rem - 1;
          addr_reg         <= next_addr;
          addr_phase_valid <= 1'b0;  // Will trigger new ADDR state
          // data_phase_active stays 1 for burst continuation
        end else begin
          // End of burst
          addr_phase_valid  <= 1'b0;
          data_phase_active <= 1'b0;
        end
      end
      
      // Reset address phase valid when not in a transaction
      if (state == IDLE) begin
        addr_phase_valid  <= 1'b0;
        data_phase_active <= 1'b0;
      end
    end
  end

endmodule