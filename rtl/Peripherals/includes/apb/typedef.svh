// Stub: apb/typedef.svh
// Provides APB_TYPEDEF macros matching PULP apb package.
// Field names match PULP convention: paddr, pprot, psel, penable, pwrite, pwdata, pstrb

`ifndef APB_TYPEDEF_SVH
`define APB_TYPEDEF_SVH

`define APB_TYPEDEF_REQ_T(__name, __addr_t, __data_t, __strb_t) \
  typedef struct packed { \
    __addr_t paddr;   \
    logic [2:0] pprot; \
    logic    psel;    \
    logic    penable; \
    logic    pwrite;  \
    __data_t pwdata;  \
    __strb_t pstrb;   \
  } __name;

`define APB_TYPEDEF_RESP_T(__name, __data_t) \
  typedef struct packed { \
    logic    pready;  \
    __data_t prdata;  \
    logic    pslverr; \
  } __name;

`define APB_TYPEDEF_ALL(__name, __addr_t, __data_t, __strb_t) \
  `APB_TYPEDEF_REQ_T(__name``_req_t, __addr_t, __data_t, __strb_t) \
  `APB_TYPEDEF_RESP_T(__name``_resp_t, __data_t)

`endif
