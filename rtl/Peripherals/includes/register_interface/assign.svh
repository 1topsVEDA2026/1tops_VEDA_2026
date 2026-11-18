// Stub: register_interface/assign.svh
// Provides REG_BUS_ASSIGN macros matching PULP register_interface.

`ifndef REGISTER_INTERFACE_ASSIGN_SVH
`define REGISTER_INTERFACE_ASSIGN_SVH

`define REG_BUS_ASSIGN_TO_REQ(__req, __intf) \
  assign __req.addr  = __intf.addr;  \
  assign __req.wdata = __intf.wdata; \
  assign __req.wstrb = __intf.wstrb; \
  assign __req.write = __intf.write; \
  assign __req.valid = __intf.valid;

`define REG_BUS_ASSIGN_FROM_RSP(__intf, __rsp) \
  assign __intf.rdata = __rsp.rdata; \
  assign __intf.error = __rsp.error; \
  assign __intf.ready = __rsp.ready;

`endif
