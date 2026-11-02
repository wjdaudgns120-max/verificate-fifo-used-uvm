`include "uvm_macros.svh"
import uvm_pkg::*;

interface fifo_if(input clk);
	logic rst;
	logic push;
	logic pop;
	logic full;
	logic empty;
	logic [7:0] wdata;
	logic [7:0] rdata;

	clocking mon_cb @ (posedge clk);
		default input #1step;
		input push, pop, wdata, rdata, full, empty;
	endclocking

endinterface

// seq item
class fifo_seq_item extends uvm_sequence_item;

	rand logic		 push;
	rand logic		 pop;
	rand logic [7:0] wdata;
		 logic [7:0] rdata;
		 logic		 full;
		 logic		 empty;

	constraint c_push_pop {
		push dist { 1 := 1, 0 := 1 };
		pop  dist { 1 := 1, 0 := 1 };
	}

	`uvm_object_utils_begin(fifo_seq_item)
		`uvm_field_int(push, UVM_DEFAULT)
		`uvm_field_int(pop, UVM_DEFAULT)
		`uvm_field_int(full, UVM_DEFAULT)
		`uvm_field_int(empty, UVM_DEFAULT)
		`uvm_field_int(wdata, UVM_DEFAULT)
		`uvm_field_int(rdata, UVM_DEFAULT)
	`uvm_object_utils_end

	function new(string name = "fifo_seq_item");
		super.new(name);
	endfunction

	function string convert2string();
		return $sformatf("\npush=%d, pop=%d, wdata=%d, rdata=%d, full=%d, empty=%d", push, pop, wdata, rdata, full, empty);
	endfunction

endclass

class fifo_sequence extends uvm_sequence#(fifo_seq_item);
	`uvm_object_utils(fifo_sequence)
	fifo_seq_item f_item;

	function new(string name = "fifo_seq");
		super.new(name);
	endfunction

	virtual task body();

		repeat(1500) begin

			f_item = fifo_seq_item::type_id::create("fifo_seq_item");
			
			start_item(f_item);
				if(!f_item.randomize()) begin
					`uvm_fatal(get_type_name(), "fifo_item_randomized fail")
				end
			finish_item(f_item);
		end

	endtask

endclass

class fifo_driver extends uvm_driver #(fifo_seq_item);
	`uvm_component_utils(fifo_driver)

	virtual fifo_if f_if;

	fifo_seq_item f_item;

	function new(string name = "fifo_drv", uvm_component c = null);
		super.new(name, c);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if( !uvm_config_db#(virtual fifo_if)::get(this, "", "f_if", f_if))
			`uvm_fatal("fifo_drv", "build_phase:can't access virtual interface");
	endfunction

	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
		f_if.push <= 0;
		f_if.pop  <= 0;
		f_if.wdata  <= 0;

		wait(!f_if.rst);
		forever begin
			seq_item_port.get_next_item(f_item);

			// drive
			@(negedge f_if.clk);
			f_if.push	<= f_item.push;
			f_if.pop	<= f_item.pop;
			f_if.wdata	<= f_item.wdata;

			seq_item_port.item_done();
		end

	endtask

endclass

class fifo_monitor extends uvm_monitor;
	`uvm_component_utils(fifo_monitor)
	uvm_analysis_port#(fifo_seq_item) send;
	virtual fifo_if f_if;
	fifo_seq_item f_item;

	function new (string name = "fifo_mon", uvm_component c = null);
		super.new(name, c);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if ( !uvm_config_db#(virtual fifo_if)::get(this, "", "f_if", f_if))
			`uvm_fatal("fifo_mon", "build_phase : can't access virtual interface");

		send = new("write", this);
	endfunction

	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);

		wait(!f_if.rst);

		forever begin
			f_item = fifo_seq_item::type_id::create("fifo_seq_item");

			@(f_if.mon_cb);

			f_item.push	 = f_if.mon_cb.push;
			f_item.pop   = f_if.mon_cb.pop;
			f_item.wdata = f_if.mon_cb.wdata;
			f_item.rdata = f_if.mon_cb.rdata;
			f_item.full	 = f_if.mon_cb.full;
			f_item.empty = f_if.mon_cb.empty;

			send.write(f_item);
		end
	endtask

endclass

class fifo_agent extends uvm_agent;
	`uvm_component_utils(fifo_agent)

	fifo_driver						fifo_drv;
	fifo_monitor					fifo_mon;
	uvm_sequencer#(fifo_seq_item)	fifo_sqr;
	
	function new(string name = "fifo_agt", uvm_component c = null);
		super.new(name, c);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		fifo_drv = fifo_driver::type_id::create("drv", this);
		fifo_mon = fifo_monitor::type_id::create("mon", this);
		fifo_sqr = uvm_sequencer#(fifo_seq_item)::type_id::create("sqr", this);
	endfunction

	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		fifo_drv.seq_item_port.connect(fifo_sqr.seq_item_export);
	endfunction

endclass

class fifo_scoreboard extends uvm_scoreboard;
	`uvm_component_utils(fifo_scoreboard)
	uvm_analysis_imp#(fifo_seq_item, fifo_scoreboard) recv;

	logic [7:0] ref_fifo [$];
	int pass_cnt = 0, fail_cnt = 0, skip_cnt = 0;

	function new(string name = "fifo_scb", uvm_component c = null);
		super.new(name, c);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		recv = new("READ", this);
	endfunction

	virtual function void write(fifo_seq_item f_item);
		logic [7:0] expected_data;

		// push
		if(f_item.push && !f_item.full) begin
			ref_fifo.push_back(f_item.wdata);
		end

		// pop
		if(f_item.pop && !f_item.empty) begin
			if(ref_fifo.size() > 0) begin
				expected_data = ref_fifo.pop_front();
				if(f_item.rdata === expected_data) begin
					`uvm_info("SCB", $sformatf("PASS! Pop Data Match: Expec_data:%d, Data:%d", expected_data, f_item.rdata), UVM_HIGH)
					pass_cnt++;
				end else begin
					`uvm_info("SCB", $sformatf("FAIL! Push:%d, Pop:%d, Wdata:%d, Rdata:%d, Expec_data:%d, full:%d, empty:%d", f_item.push, f_item.pop, f_item.wdata, f_item.rdata, expected_data, f_item.full, f_item.empty), UVM_NONE);
					fail_cnt++;
				end
			end
		end
	endfunction

	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);

		`uvm_info("SCB", $sformatf("**********************************"), UVM_NONE);
		`uvm_info("SCB", $sformatf("********* pass count = %2d *********", pass_cnt), UVM_NONE);
		`uvm_info("SCB", $sformatf("********* fail count = %2d *********", fail_cnt), UVM_NONE);
		`uvm_info("SCB", $sformatf("**********************************\n"), UVM_NONE);

	endfunction

endclass

// coverage
class fifo_coverage extends uvm_subscriber#(fifo_seq_item);
	`uvm_component_utils(fifo_coverage)

	fifo_seq_item f_item;

	covergroup fifo_cg;
		option.per_instance = 1;

		cp_push: coverpoint f_item.push { bins push[] = {0, 1}; }
		cp_pop:  coverpoint f_item.pop  { bins pop[]  = {0, 1}; }

		cp_full:  coverpoint f_item.full	{ bins full[]   = {0, 1}; }
		cp_empty: coverpoint f_item.empty	{ bins empty[]  = {0, 1}; }

		cp_wdata: coverpoint f_item.wdata { bins wdata[] = {[0:255]}; }

		// cross coverage
		cx_push_pop:	cross cp_push, cp_pop;
		cx_full_empty:	cross cp_full, cp_empty {ignore_bins invalid_full_empty = binsof(cp_full) intersect{1} && binsof(cp_empty) intersect{1}; }

	endgroup

	function new(string name = "fifo_cov", uvm_component c = null);
		super.new(name, c);
		fifo_cg = new();
	endfunction

	virtual function void write(fifo_seq_item t);
		f_item = t;
		fifo_cg.sample(); // sample, bins one time hit
	endfunction

	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		`uvm_info("COV", $sformatf("*********Coverage Report**********"), UVM_NONE);
		`uvm_info("COV", $sformatf("*** Overall		= %5.1f%% ***", fifo_cg.get_coverage()), UVM_NONE);
		`uvm_info("COV", $sformatf("*** push		= %5.1f%% ***", fifo_cg.cp_push.get_coverage()), UVM_NONE);
		`uvm_info("COV", $sformatf("*** pop			= %5.1f%% ***", fifo_cg.cp_pop.get_coverage()), UVM_NONE);
		`uvm_info("COV", $sformatf("*** wdata		= %5.1f%% ***", fifo_cg.cp_wdata.get_coverage()), UVM_NONE);
		`uvm_info("COV", $sformatf("*** full		= %5.1f%% ***", fifo_cg.cp_full.get_coverage()), UVM_NONE);
		`uvm_info("COV", $sformatf("*** empty		= %5.1f%% ***", fifo_cg.cp_empty.get_coverage()), UVM_NONE);
		`uvm_info("COV", $sformatf("*** push/pop	= %5.2f%% ***", fifo_cg.cx_push_pop.get_coverage()), UVM_NONE);
		`uvm_info("COV", $sformatf("*** full_empty	= %5.2f%% ***", fifo_cg.cx_full_empty.get_coverage()), UVM_NONE);
		`uvm_info("COV", $sformatf("**********************************\n"), UVM_NONE);
	endfunction

endclass

class fifo_environment extends uvm_env;
	`uvm_component_utils(fifo_environment)
	fifo_agent		fifo_agt;
	fifo_scoreboard	fifo_scb;
	fifo_coverage	fifo_cov;

	function new(string name = "fifo_env", uvm_component c = null);
		super.new(name, c);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		fifo_agt = fifo_agent::type_id::create("agt", this);
		fifo_scb = fifo_scoreboard::type_id::create("scb", this);
		fifo_cov = fifo_coverage::type_id::create("cov", this);
	endfunction

	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		fifo_agt.fifo_mon.send.connect(fifo_scb.recv);
		fifo_agt.fifo_mon.send.connect(fifo_cov.analysis_export); // monitor : caller, scoreboard, coverage: callee
	endfunction
endclass

class fifo_test extends uvm_test;
	`uvm_component_utils(fifo_test)

	fifo_sequence	 fifo_seq;
	fifo_environment fifo_env;

	function new(string name = "fifo_test", uvm_component c = null);
		super.new(name, c);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		fifo_seq = fifo_sequence::type_id::create("seq", this);
		fifo_env = fifo_environment::type_id::create("env", this);
	endfunction

	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);
		phase.raise_objection(this);
			fifo_seq.start(fifo_env.fifo_agt.fifo_sqr);
		phase.drop_objection(this);
	endtask
endclass


module tb_fifo_uvm();

	logic clk = 0;
	always #5 clk = ~clk;

	fifo_if f_if(clk);

	fifo_uvm dut(
		.clk	(clk),
		.rst	(f_if.rst),
		.push	(f_if.push),
		.pop	(f_if.pop),
		.wdata	(f_if.wdata),
		.rdata	(f_if.rdata),
		.full	(f_if.full),
		.empty	(f_if.empty)
	);

	initial begin
		f_if.rst  = 1;
		f_if.push = 0;
		f_if.pop  = 0;

		#10;
		f_if.rst = 0;


	end

	initial begin
		$fsdbDumpfile("wave.fsdb");
		$fsdbDumpvars(0, tb_fifo_uvm);
	end

	initial begin
		uvm_config_db #(virtual fifo_if)::set(null, "*", "f_if", f_if);
		run_test("fifo_test");
	end

endmodule


