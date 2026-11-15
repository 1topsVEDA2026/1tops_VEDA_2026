// =============================================================================
// APB Master Agent
// =============================================================================
// UVM agent encapsulating driver + monitor + sequencer for APB master.
// Can be configured as active (with driver) or passive (monitor only).

class apb_master_agent extends uvm_agent;

    `uvm_component_utils(apb_master_agent)

    apb_master_driver    driver;
    apb_monitor          monitor;
    uvm_sequencer #(apb_transaction) sequencer;

    function new(string name = "apb_master_agent", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        monitor = apb_monitor::type_id::create("monitor", this);

        if (get_is_active() == UVM_ACTIVE) begin
            driver    = apb_master_driver::type_id::create("driver", this);
            sequencer = uvm_sequencer#(apb_transaction)::type_id::create("sequencer", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : apb_master_agent
