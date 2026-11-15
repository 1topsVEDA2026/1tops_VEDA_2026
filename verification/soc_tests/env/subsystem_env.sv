// =============================================================================
// Subsystem UVM Environment
// =============================================================================
// Top-level environment: instantiates APB agent, scoreboard, functional
// coverage collector, and virtual sequencer. Connects monitor → ports.

class subsystem_env extends uvm_env;

    `uvm_component_utils(subsystem_env)

    apb_master_agent            apb_agent;
    subsystem_scoreboard        scoreboard;
    subsystem_virtual_sequencer v_sqr;
    subsystem_coverage          coverage;

    function new(string name = "subsystem_env", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        apb_agent  = apb_master_agent::type_id::create("apb_agent", this);
        scoreboard = subsystem_scoreboard::type_id::create("scoreboard", this);
        v_sqr      = subsystem_virtual_sequencer::type_id::create("v_sqr", this);
        coverage   = subsystem_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect monitor analysis port to scoreboard and coverage
        apb_agent.monitor.ap.connect(scoreboard.ap_imp);
        apb_agent.monitor.ap.connect(coverage.analysis_export);

        // Give virtual sequencer access to APB sequencer
        v_sqr.apb_sqr = apb_agent.sequencer;
    endfunction

endclass : subsystem_env
