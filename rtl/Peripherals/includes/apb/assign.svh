// Stub: apb/assign.svh
// Provides APB_ASSIGN macros matching PULP apb package.

`ifndef APB_ASSIGN_SVH
`define APB_ASSIGN_SVH

`define APB_ASSIGN_TO_REQ(__req, __intf) \
  assign __req.paddr   = __intf.paddr;   \
  assign __req.pprot   = __intf.pprot;   \
  assign __req.psel    = __intf.psel;    \
  assign __req.penable = __intf.penable; \
  assign __req.pwrite  = __intf.pwrite;  \
  assign __req.pwdata  = __intf.pwdata;  \
  assign __req.pstrb   = __intf.pstrb;

`define APB_ASSIGN_FROM_RESP(__intf, __rsp) \
  assign __intf.pready  = __rsp.pready;  \
  assign __intf.prdata  = __rsp.prdata;  \
  assign __intf.pslverr = __rsp.pslverr;

`endif
