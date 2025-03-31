`ifndef APB_IF_DEF
`define APB_IF_DEF

interface apb_if #(D_WIDTH = 64) (input pclk);
	logic presetn;
	logic [31:0] paddr;
	logic psel;
	logic penable;
	logic pwrite;
	logic [D_WIDTH-1:0] pwdata;
	logic [D_WIDTH/8-1:0] pstrb;
	logic pready;
	logic [D_WIDTH-1:0] prdata;
	logic pslverr;

	task automatic init();
		begin
			{psel, penable, pwrite} = '0;
		end
	endtask

	task automatic write(
		  input int delay
		, input [3:0] id, input [31:0] address
		, input int length, input int size
		, input [1:0] burst, input [1:0] lock, input [2:0] prot
		, ref logic [7:0] data [$]
	);
		// address stage
		logic [D_WIDTH-1:0] bus_data;
		int randdelay;
		paddr = address;
		psel = 0;
		pstrb = '1;
		pwrite = 1'b0;
		penable = 1'b0;
		pwdata = '0;
		@(posedge pclk);
		psel = 1'b1;
		pwrite = 1;
		for (int j = 0; j < length; j++) begin
			// data stage
			bus_data = 0;
			pwdata = 0;
			penable = 0;
			randdelay = $urandom_range(1,3);
			if (randdelay > 0) begin
				repeat (randdelay) @(posedge pclk);
			end
			penable = 1;
			pstrb = '0;
			if (data.size() >= D_WIDTH/8) begin
				pstrb = '1;
				for (int i = 0; i < D_WIDTH/8; i++)
					bus_data[i*8 +: 8] = data.pop_front();
			end else begin
				pstrb = '0;
				for (int i = 0; i < data.size(); i++) begin
					pstrb[i] = '1;
					bus_data[i*8 +: 8] = data.pop_front();
				end
			end
			pwdata = bus_data;
			do
				@(negedge pclk);
			while (!pready);
			@(posedge pclk);
			paddr += D_WIDTH/8;
		end
		psel = 0;
		penable = 0;
		pwdata = '0;
		@(posedge pclk);
	endtask : write

	task automatic read(
		  input int delay
		, input [3:0] id, input [31:0] address
		, input int length, input int size
		, input [1:0] burst, input [1:0] lock, input [2:0] prot
		, ref logic [7:0] data [$]
	);
		logic [D_WIDTH-1:0] bus_data;
		int randdelay;
		paddr = address;
		bus_data = 0;
		pwdata = 0;
		psel = 0;
		pstrb = '1;
		pwrite = 1'b0;
		penable = 1'b0;
		pwdata = '0;
		@(posedge pclk);
		psel = 1'b1;
		pwrite = 0;
		for (int j = 0; j < length; j++) begin
			penable = 0;
			randdelay = $urandom_range(1,3);
			if (randdelay > 0) begin
				repeat (randdelay) @(posedge pclk);
			end
			penable = 1'b1;
			do begin
				@(negedge pclk);
				bus_data = prdata;
			end while (!pready);
			for (int i = 0; i < (1<<size); i++)
				data.push_back(bus_data[i*8 +: 8]);
			@(posedge pclk);
			paddr += D_WIDTH/8;
		end
		psel = 0;
		penable = 0;
		@(posedge pclk);
	endtask : read

	clocking cb @(posedge pclk);
		input prdata;
		input pready;
		output psel;
		output penable;
		output pwdata;
		output paddr;
		output pstrb;
		output pwrite;
	endclocking

	modport mst (
		  input pclk
		, clocking cb
		, import write, import read, import init
	);

	modport slv (
		  input pclk
		, input presetn
		, input paddr
		, input psel
		, input penable
		, input pwrite
		, input pwdata
		, input pstrb
		, output pready
		, output prdata
		, output pslverr
	);


endinterface : apb_if

`endif // APB_IF_DEF