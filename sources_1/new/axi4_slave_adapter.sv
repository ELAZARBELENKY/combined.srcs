/*
 *  Copyright © 2025 FortifyIQ, Inc.
 *
 *  All Rights Reserved.
 *
 *  All information contained herein is, and remains, the property of FortifyIQ, Inc.
 *  Dissemination of this information or reproduction of this material, in any medium,
 *  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
 *
 */

/*
  AXI4 slave adapter. Features:
  * BURST support
  * No interleaving support
  * No protection unit
  * No exclusive access
  * No queue
*/
//`define FIQ_AXI_TRANSACTIONS_QUEUE_SUPPORT
module axi4_slave_adapter #(
    parameter int D_WIDTH                 = 'd32
`ifdef FIQ_AXI_TRANSACTIONS_QUEUE_SUPPORT
  , parameter int TRANSACTIONS_QUEUE_SIZE = 'd1  // >1 - interleaving is enabled
`endif
  , parameter bit LAST_EN                 = 1'b1
  , parameter int AXI_A_WIDTH             = 'd32
  , parameter int CON_A_WIDTH             = 'd12
  , parameter bit SIMULTANEOUS_RW         = 1'b1 // 0 - only a read or a write may happen at a time
  , parameter bit WRITE_PRIORITY          = 1'b1 // 1 - writes are granted before reads
) (
    input  logic                   aclk
  , input  logic                   aresetn
  // Write address channel signals
  , input  logic [3:0]             awid
  , input  logic [AXI_A_WIDTH-1:0] awaddr
  , input  logic [7:0]             awlen
  , input  logic [2:0]             awsize
  , input  logic [1:0]             awburst
  , input  logic [1:0]             awlock
  , input  logic [2:0]             awprot
  , input  logic                   awvalid
  , output logic                   awready
  // Write data channel signals
  , input  logic [3:0]             wid
  , input  logic [D_WIDTH-1:0]     wdata
  , input  logic [D_WIDTH/8-1:0]   wstrb
  , input  logic                   wlast
  , input  logic                   wvalid
  , output logic                   wready
  // Write response channel signals
  , output logic [3:0]             bid
  , output logic [1:0]             bresp
  , output logic                   bvalid
  , input  logic                   bready
  // Read address channel signals
  , input  logic [3:0]             arid
  , input  logic [AXI_A_WIDTH-1:0] araddr
  , input  logic [7:0]             arlen
  , input  logic [2:0]             arsize
  , input  logic [1:0]             arburst
  , input  logic [1:0]             arlock
  , input  logic [2:0]             arprot
  , input  logic                   arvalid
  , output logic                   arready
  // Read data channel signals
  , output logic [3:0]             rid
  , output logic [D_WIDTH-1:0]     rdata
  , output logic [1:0]             rresp
  , output logic                   rlast
  , output logic                   rvalid
  , input  logic                   rready
  // Conduit connectivity
  , output logic                   con_wr             // write command from bus
  , output logic                   con_rd             // read command from bus
  , output logic                   con_rd_ack         // acknowledge of reading on bus
  , input  logic                   con_ready_for_read // 1 when connected host is ready for read
  , input  logic                   con_overflow       // input buffer overflow to set wready to 0
  , output logic [CON_A_WIDTH-1:0] con_waddr          // write address
  , output logic [CON_A_WIDTH-1:0] con_raddr          // read  address
  , output logic [D_WIDTH-1:0]     con_wdata          // write data
  , output logic [D_WIDTH/8-1:0]   con_wbyte_enable   // bytes of write data enable strobe
  , output logic [D_WIDTH/8-1:0]   con_rbyte_enable   // bytes of read data enable strobe
  , input  logic [D_WIDTH-1:0]     con_rdata          // read data
  , input  logic                   con_read_valid     // read data validation strobe
  , input  logic                   con_slv_error      // slave error flag from interfacing module, expected one cycle after request
  , input  logic                   break_transaction  // break transaction. connected host may break the current transaction
  , output logic                   wstuck
  , output logic                   rstuck
  , output logic                   fixed_read_burst
  , output logic                   fixed_write_burst
);

  // for further development there are read and write queues.
  // queues consist of transaction state slices. Each state includes information about
  // address, length, size, id, burst flag, etc. and active flag
  // which is to mark current transaction as in processing. But for now its depth is only 1.
  typedef struct packed {
    logic [3:0]             id;
    logic [AXI_A_WIDTH-1:0] addr;
    logic [7:0]             len;
    logic [2:0]             size;
    logic [1:0]             burst;
    logic [1:0]             lock;  // is not used for now
    logic [2:0]             prot;  // is not used for now
    logic                   active;
  } transaction_t;

`ifdef FIQ_AXI_TRANSACTIONS_QUEUE_SUPPORT
  localparam TX_QUEUE_SZ = TRANSACTIONS_QUEUE_SIZE;
`else
  localparam TX_QUEUE_SZ = 1;
`endif

  transaction_t [TX_QUEUE_SZ-1:0] wqueue;
  transaction_t [TX_QUEUE_SZ-1:0] rqueue;

`ifndef FIQ_AXI_TRANSACTIONS_QUEUE_SUPPORT

  // If the slave has a single read/write port, allow only one read or write operation at a time
  logic grant_r, grant_w;
  if (SIMULTANEOUS_RW) begin
    assign grant_r = 1'b1;
    assign grant_w = 1'b1;
  end else if (WRITE_PRIORITY) begin
    assign grant_r = ~wqueue[0].active && ~awvalid;
    assign grant_w = ~rqueue[0].active;
  end else begin
    assign grant_r = ~wqueue[0].active;
    assign grant_w = ~rqueue[0].active && ~arvalid;
  end

  logic read_last, write_last;
  logic break_req;
  logic [1:0] read_resp, write_resp;

  assign arready = ~break_req & ~rqueue[0].active && grant_r; // ready when there are no active transactions
  assign awready = ~break_req & ~wqueue[0].active && grant_w;
  // ready for write when write transaction is active, no Ibuf overflow and response is received
  assign wready = wqueue[0].active & ~con_overflow & ~(bvalid & ~bready);
  // connect with ports of interfacing module
  assign con_waddr = wqueue[0].addr[CON_A_WIDTH-1:0];
  assign con_raddr = rqueue[0].addr[CON_A_WIDTH-1:0];
  assign con_wdata = wdata;
  assign con_wbyte_enable = wstrb;
  assign con_rbyte_enable = '1;
  assign con_wr = ~break_req & wvalid & wready;
  assign wstuck = (wqueue[0].active & wvalid & ~wready);
  assign rstuck = (rqueue[0].active & ~rvalid & rready);
  // read - when read transaction is active and when ext module is ready for read.
  // !rlast - is a cut-off to avoid extra reads when last read is done but transaction is not end-off yet
  assign con_rd = ~break_req && rqueue[0].active && rready && !rlast;
  // read is considered performed when transaction is active and data is read (rready && rvalid)
  assign con_rd_ack = !break_req && rqueue[0].active && rready && rvalid;
  assign rlast = rvalid && read_last;
  assign rresp = (con_slv_error ? 2'd2 : 2'd0) | read_resp;
  assign bresp = (con_slv_error ? 2'd2 : 2'd0) | write_resp;

  assign bid = wqueue[0].id;
  assign rid = rqueue[0].id;

  logic [AXI_A_WIDTH-1:0] w_wrap_mask;
  logic [AXI_A_WIDTH-1:0] r_wrap_mask;

  logic [2:0]  weight;
  logic [10:0] next_wrapped_addr;

  assign fixed_read_burst  = (rqueue[0].burst == 2'b00) && (wqueue[0].len != 8'h0);
  assign fixed_write_burst = (wqueue[0].burst == 2'b00) && (wqueue[0].len != 8'h0);

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      wqueue[0]  <= '0;
      rqueue[0]  <= '0;
      bvalid     <= '0;
      read_last  <= '0;
      break_req  <= 1'b0;
      rvalid     <= 1'b0;
      rdata      <= '0;
      write_resp <= '0;
      read_resp  <= '0;
    end else begin
      if (rqueue[0].active) begin
        if (rready && rvalid && rlast) begin
          rvalid <= 1'b0;
          read_resp  <= 2'b00;
        end else if (rready && rvalid && break_req) begin
          read_resp <= 2'b10;
        end else if (break_req && ~rvalid) begin
          rvalid <= 1'b1;
          read_resp  <= 2'b10;
        end else if (con_read_valid || con_slv_error) begin
          rvalid <= 1'b1;
          rdata  <= con_rdata;
          read_resp  <= {con_slv_error, 1'b0};
        end else if (con_rd_ack)
          rvalid <= 1'b0;
      end else begin
        rvalid <= 1'b0;
        read_resp <= '0;
        read_resp <= 2'b00;
      end
      if (break_transaction)
        break_req <= 1'b1;
      else if (
          break_req
        && ((rqueue[0].active && rready && rvalid && (rlast || rresp[1])) || !rqueue[0].active)
        && ((wqueue[0].active && bvalid && bready) || !wqueue[0].active)
      ) begin
        break_req <= 1'b0;
        read_last <= '0;
      end
      // capture address channels
      if (awvalid && !wqueue[0].active && !break_req && grant_w) begin
        wqueue[0] <= {awid, awaddr, awlen, awsize, awburst, awlock, awprot, 1'b1};
        if (awlen[3]) begin
          weight = 3'd4;
        end else if (awlen[2]) begin
          weight = 3'd3;
        end else if (awlen[1]) begin
          weight = 3'd2;
        end else if (awlen[0]) begin
          weight = 3'd1;
        end else begin
          weight = 3'd0;
        end
        w_wrap_mask <= {AXI_A_WIDTH{1'b1}} << (awsize + weight);
      end
      if (arvalid && !rqueue[0].active && !break_req && grant_r) begin
        rqueue[0] <= {arid, araddr, arlen, arsize, arburst, arlock, arprot, 1'b1};
        read_last <= arlen == 8'h0;
        if (arlen[3]) begin
          weight = 3'd4;
        end else if (arlen[2]) begin
          weight = 3'd3;
        end else if (arlen[1]) begin
          weight = 3'd2;
        end else if (awlen[0]) begin
          weight = 3'd1;
        end else begin
          weight = 3'd0;
        end
        r_wrap_mask <= {AXI_A_WIDTH{1'b1}} << (arsize + weight);
      end
      // write data & response channels
      if (wvalid && wqueue[0].len != 8'h0) begin
        case (wqueue[0].burst)
          2'b01: wqueue[0].addr <= wqueue[0].addr + (1 << wqueue[0].size);
          2'b10: begin
            next_wrapped_addr = (wqueue[0].addr[10:0] + (1 << wqueue[0].size));
            wqueue[0].addr <=
                (wqueue[0].addr & w_wrap_mask)
              | ({21'h0, next_wrapped_addr} & ~w_wrap_mask);
          end
          default: begin
          end
        endcase // wqueue[0].awburst
        wqueue[0].len <= wqueue[0].len - 8'h1;
      end
      if (bvalid && bready) begin // resp channel released
        bvalid <= 1'b0;
        write_resp  <= 2'b00;
      end else if ((wqueue[0].active || bvalid) && ~|write_resp) begin
        write_resp <= (con_slv_error | break_req) ? 2'b10 : 2'b00;
      end
      if (wvalid && wlast && wready) begin // end of write transaction
        wqueue[0].active <= 1'b0;
        bvalid <= 1'b1; // resp channel assertion
      end
      // read data channel
      if (rqueue[0].len > 8'h0) begin // read address control for burst
        if (rready && con_read_valid && con_ready_for_read) begin
          case (rqueue[0].burst)
            2'b01: rqueue[0].addr <= rqueue[0].addr + (1 << rqueue[0].size);
            2'b10: begin
              next_wrapped_addr = (rqueue[0].addr[10:0] + (1 << rqueue[0].size));
              rqueue[0].addr <=
                  (rqueue[0].addr & r_wrap_mask)
                | ({21'h0, next_wrapped_addr} & ~r_wrap_mask);
            end
            default: begin
            end
          endcase // wqueue[0].awburst
        end
        if (rready && rvalid) begin
          rqueue[0].len <= rqueue[0].len - 8'h1;
          read_last <= rqueue[0].len == 8'h1;
        end
      end
      if (rlast && rready && rvalid) begin
        rqueue[0].active <= 1'b0;
      end
    end
  end

`endif

endmodule