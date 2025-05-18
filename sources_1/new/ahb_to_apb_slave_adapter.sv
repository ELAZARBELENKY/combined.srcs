/*
 *  Copyright © 2024 FortifyIQ, Inc.
 *
 *  All Rights Reserved.
 *
 *  All information contained herein is, and remains, the property of FortifyIQ, Inc.
 *  Dissemination of this information or reproduction of this material, in any medium,
 *  is strictly forbidden unless prior written permission is obtained from FortifyIQ, Inc.
 *
 */

module ahb_to_apb_slave_adapter
#(
  parameter int AHB_DATA_WIDTH = 'd64,
  parameter int APB_DATA_WIDTH = 'd32,
  parameter int AHB_ADDR_WIDTH = 'd32,
  parameter int APB_ADDR_WIDTH = AHB_ADDR_WIDTH
) (
  //AMBA AHB Lite INF
  input  logic                      hclk_i,
  input  logic                      hreset_ni,
  input  logic [AHB_ADDR_WIDTH-1:0] haddr_i,
  input  logic [AHB_DATA_WIDTH-1:0] hwdata_i,
  input  logic                      hsel_i,
  input  logic                      hwrite_i,
  input  logic                      hready_i,
  input  logic [1:0]                htrans_i,
  input  logic [2:0]                hsize_i,
  output logic                      hresp_o,
  output logic                      hreadyout_o,
  output logic [AHB_DATA_WIDTH-1:0] hrdata_o,

  //AMBA APB INF
  output logic                      pclk_o,
  output logic                      presetn_o,
  output logic [APB_ADDR_WIDTH-1:0] paddr_o,
  output logic [APB_DATA_WIDTH-1:0] pwdata_o,
  output logic                      psel_o,
  output logic                      penable_o,
  output logic                      pwrite_o,
  input  logic                      pslverr_i,
  input  logic                      pready_i,
  input  logic [APB_DATA_WIDTH-1:0] prdata_i
);

  assign pclk_o    = hclk_i;
  assign presetn_o = hreset_ni;

  logic [APB_DATA_WIDTH-1:0] pwdata;

  // Information about two consecutive transfers
  logic [APB_DATA_WIDTH-1:0] addr[2];
  logic wr[2];

  generate
    if ((AHB_DATA_WIDTH == 32) && (APB_DATA_WIDTH == 32)) begin
      always_comb begin
        unique case (hsize_i) inside
          3'b000:  pwdata = {'0, hwdata_i[7:0]};
          3'b001:  pwdata = {'0, hwdata_i[15:0]};
          3'b010:  pwdata = hwdata_i;
          default: pwdata = hwdata_i;
        endcase
        hrdata_o = prdata_i;
      end
    end else if ((AHB_DATA_WIDTH == 64) && (APB_DATA_WIDTH == 32)) begin
      always_comb begin
        unique case (hsize_i) inside
          3'b000:  pwdata = addr[0][2] ? {'0, hwdata_i[39:32]} : {'0, hwdata_i[7:0]};
          3'b001:  pwdata = addr[0][2] ? {'0, hwdata_i[47:32]} : {'0, hwdata_i[15:0]};
          3'b010:  pwdata = addr[0][2] ? hwdata_i[63:32] : hwdata_i[31:0];
          default: pwdata = addr[0][2] ? hwdata_i[63:32] : hwdata_i[31:0];
        endcase
        hrdata_o = paddr_o[2] ? {prdata_i, 32'b0} : {32'b0, prdata_i};
      end
    end else if ((AHB_DATA_WIDTH == 64) && (APB_DATA_WIDTH == 64)) begin
      always_comb begin
        unique case (hsize_i) inside
          3'b000:  pwdata = {'0, hwdata_i[7:0]};
          3'b001:  pwdata = {'0, hwdata_i[15:0]};
          3'b010:  pwdata = addr[0][2]? hwdata_i[63:32] : hwdata_i[31:0];
          3'b011:  pwdata = hwdata_i;
          default: pwdata = hwdata_i;
        endcase
        hrdata_o = prdata_i;
      end
    end
  endgenerate

  logic tr_init;
  logic tr_stall;
  logic tr_pending;

  assign tr_init = (hsel_i && (htrans_i inside {2'b10, 2'b11})) && hready_i;

  always_ff @(posedge hclk_i or negedge hreset_ni) begin
    if(~hreset_ni) begin
      penable_o  <= 1'b0;
      psel_o     <= 1'b0;
      pwdata_o   <= '0;
      tr_stall   <= 1'b0;
      tr_pending <= 1'b0;
      addr       <= '{default:'0};
      wr         <= '{default:'0};
    end else begin
      // APB write transaction is delayed for one cycle to acquire the wdata.
      // Any transfer requested during that time is considered pending.
      if (tr_pending && wr[0]) begin
        psel_o   <= 1'b1;
      end else if (tr_init && hwrite_i && !tr_stall) begin
        psel_o   <= 1'b0;
        tr_stall <= 1'b1;
      end else if (tr_init || tr_stall || tr_pending) begin
        psel_o   <= 1'b1;
        tr_stall <= 1'b0;
      end else if (pready_i) begin
        psel_o   <= 1'b0;
      end

      if (tr_init) begin
        addr[0] <= haddr_i;
        wr[0]   <= hwrite_i;
      end

      if (tr_stall && tr_init) begin
        tr_pending <= 1'b1;
        addr <= '{haddr_i,  addr[0]};
        wr   <= '{hwrite_i, wr[0]};
      end else if (pready_i && !tr_init) begin
        tr_pending <= 1'b0;
      end else if (pready_i && tr_pending) begin
        addr <= '{haddr_i,  addr[0]};
        wr   <= '{hwrite_i, wr[0]};
      end

      penable_o <= psel_o && !pready_i;

      if (hready_i) pwdata_o <= pwdata;
    end
  end

  // Ready for the new transfer when
  // 1) no APB transfer is active, or
  // 2) an APB transfer has just ended and there are no pending transactions, or
  // 3) there is a pending AHB write transaction and we need to acquire the wdata.
  assign hreadyout_o = !psel_o
                    || (pready_i && !tr_pending)
                    || (pready_i && tr_pending && wr[0]);
  assign paddr_o  = tr_pending ? addr[1] : addr[0];
  assign pwrite_o = tr_pending ? wr[1]   : wr[0];
  assign hresp_o  = pslverr_i;

endmodule