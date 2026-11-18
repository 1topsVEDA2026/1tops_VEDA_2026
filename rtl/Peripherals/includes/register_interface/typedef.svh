// Stub: register_interface/typedef.svh
// Provides REG_BUS_TYPEDEF macros matching PULP register_interface.

`ifndef REGISTER_INTERFACE_TYPEDEF_SVH
`define REGISTER_INTERFACE_TYPEDEF_SVH

`define REG_BUS_TYPEDEF_REQ(__name, __addr_t, __data_t, __strb_t) \
  typedef struct packed { \
    __addr_t addr;  \
    __data_t wdata; \
    __strb_t wstrb; \
    logic    write; \
    logic    valid; \
  } __name;

`define REG_BUS_TYPEDEF_RSP(__name, __data_t) \
  typedef struct packed { \
    __data_t rdata; \
    logic    error; \
    logic    ready; \
  } __name;

`define REG_BUS_TYPEDEF_ALL(__name, __addr_t, __data_t, __strb_t) \
  `REG_BUS_TYPEDEF_REQ(__name``_req_t, __addr_t, __data_t, __strb_t) \
  `REG_BUS_TYPEDEF_RSP(__name``_rsp_t, __data_t)

`endif
