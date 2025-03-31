`include "interfaces.sv"
`include "enviroment.sv"
`define TEST 1
module tests (
    native_if_t.slv native_if
  , slave_adapter_if_t.mst slv_bus_if
  , apb_if.mst apb
);

  environment env;

  initial begin
    env = new(native_if, slv_bus_if, apb);
    env.init_test();
    if (`TEST == 0)
      env.run();
    else if (`TEST == 1)
      env.run_apb();
  end

endmodule