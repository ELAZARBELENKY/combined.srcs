`ifndef BASE_TYPES_DEF
`define BASE_TYPES_DEF
`define ARCH_SZ `WORD_SIZE

//typedef logic [`ARCH_SZ-1:0] data_t [16];
//typedef logic [`ARCH_SZ-1:0] state_t [8];
//typedef state_t init_state_shares_t [3];
typedef logic [`ARCH_SZ-1:0] data_t [16];
typedef logic [`ARCH_SZ-1:0] state_t [8];
typedef struct {
	int delay;
	logic [3:0] id;
	logic [31:0] address;
	int length;
	int size;
	logic [1:0] burst;
	logic [1:0] lock;
	logic [2:0] prot;
//	logic [`FIQSHA_BUS_DATA_WIDTH-1:0] data [$];
  logic [`WORD_SIZE-1:0] data [$];
	logic [1:0] resp;
	logic active;
} transaction_t;

typedef struct {
	int id;
	data_t msg [$];
//	init_state_shares_t init_state_shares;
	state_t hash;
	logic hmac;
} test_cfg_t;

// function logic[7:0] fromByte(input byte b);


`endif // BASE_TYPES_DEF