`timescale 1ns / 1ps
localparam BUS_WIDTH = `FIQSHA_BUS;
localparam ADDR_SP_SZ = 12;
module lw_sha_ahb_top(
  // Clock and reset
  input  logic                   hclk,
  input  logic                   hresetn,
  // AHB inferface
input  logic [ADDR_SP_SZ-1:0]    haddr,
input  logic [2:0]               hsize,
input  logic [1:0]               htrans,
input  logic [BUS_WIDTH-1:0]     hwdata,
input  logic                     hwrite,
input  logic                     hsel,
input  logic                     hready,
output logic [BUS_WIDTH-1:0]     hrdata,
output logic                     hreadyout,
output logic                     hresp,
input  logic [3:0]               random_i
`ifdef HMACAUXKEY
input  logic [`KEY_SIZE-1:0]     aux_key_i,
`endif
);
logic pclk, presetn, psel, penable, pwrite, pslverr, pready;
logic [ADDR_SP_SZ-1:0] paddr;
logic [BUS_WIDTH-1:0] prdata, pwdata;

ahb_to_apb_slave_adapter #(
  .AHB_DATA_WIDTH(`FIQSHA_BUS),   // or 32
  .APB_DATA_WIDTH(`FIQSHA_BUS),   // or 64, as needed
  .AHB_ADDR_WIDTH(12),
  .APB_ADDR_WIDTH(12)
) u_ahb_to_apb_adapter (
  // AHB inputs
  .hclk_i      (hclk),
  .hreset_ni   (hresetn),
  .haddr_i     (haddr),
  .hwdata_i    (hwdata),
  .hsel_i      (hsel),
  .hwrite_i    (hwrite),
  .hready_i    (hready),
  .htrans_i    (htrans),
  .hsize_i     (hsize),
  .hresp_o     (hresp),
  .hreadyout_o (hreadyout),
  .hrdata_o    (hrdata),

  // APB outputs/inputs
  .pclk_o      (pclk),
  .presetn_o   (presetn),
  .paddr_o     (paddr),
  .pwdata_o    (pwdata),
  .psel_o      (psel),
  .penable_o   (penable),
  .pwrite_o    (pwrite),
  .pslverr_i   (pslverr),
  .pready_i    (pready),
  .prdata_i    (prdata)
);

lw_sha_apb_top u_ahb_top (
    .pclk(pclk),
    .presetn(presetn),
    .paddr(paddr),
    .psel(psel),
    .penable(penable),
    .pwrite(pwrite),
    .pwdata(pwdata),
    .pstrb('0),
    .pready(pready),
    .prdata(prdata),
    .pslverr(pslverr),
    .random_i(random_i)
`ifdef HMACAUXKEY
    ,.aux_key_i(aux_key_i)
`endif
    );

endmodule
