
module fifo_uvm(
	input  logic	   clk,
	input  logic	   rst,
	input  logic	   push,
	input  logic	   pop,
	input  logic [7:0] wdata,
	output logic [7:0] rdata,
	output logic 	   full,
	output logic	   empty
);

	logic [1:0] w_wptr, w_rptr;

	wire we = push && !full;

	ram U_RAM(
		.clk	(clk),
		.we		(we),
		.waddr	(w_wptr),
		.raddr	(w_rptr),
		.wdata	(wdata),
		.rdata	(rdata)
	);
	control_unit U_CONTROL_UNIT(
		.clk	(clk),
		.rst	(rst),
		.push	(push),
		.pop	(pop),
		.full	(full),
		.empty	(empty),
		.wptr	(w_wptr),
		.rptr	(w_rptr)
	);

endmodule

module ram(
	input	logic		 clk,
	input 	logic		 we,
	input 	logic [1:0] waddr,
	input 	logic [1:0] raddr,
	input 	logic [7:0]  wdata,
	output	logic [7:0]  rdata
);

	logic [7:0] mem[0:3];

	always_ff @(posedge clk)begin
		if (we) mem[waddr] <= wdata;
	end

	// CL output
	assign rdata = mem[raddr];

endmodule

module control_unit(
	input  logic		clk,
	input  logic 		rst,
	input  logic 		push,
	input  logic 		pop,
	output logic 		full,
	output logic 		empty,
	output logic [1:0]	wptr,
	output logic [1:0] 	rptr
);

	logic full_next, full_reg;
	logic empty_next, empty_reg;
	logic [1:0] wptr_next, wptr_reg;
	logic [1:0] rptr_next, rptr_reg;

	assign full = full_reg;
	assign empty = empty_reg;
	assign wptr = wptr_reg;
	assign rptr = rptr_reg;

	// SL
	always_ff @(posedge clk, posedge rst)begin
		if(rst)begin
			wptr_reg  <= 0;
			rptr_reg  <= 0;
			full_reg  <= 0;
			empty_reg <= 1;
		end else begin
			wptr_reg  <= wptr_next;
			rptr_reg  <= rptr_next;
			full_reg  <= full_next;
			empty_reg <= empty_next;
		end
	end

	// CL & output
	always_comb begin
		wptr_next  = wptr_reg;
		rptr_next  = rptr_reg;
		full_next  = full_reg;
		empty_next = empty_reg;

		case( { push, pop } )
			2'b00: begin
				// init
			end
			// only pop
			2'b01: begin
				if(!empty_reg) begin
					rptr_next = rptr_reg + 1;
					full_next = 0;
					if(wptr_reg == rptr_next) empty_next = 1;
				end
			end
			// only push
			2'b10: begin
				if(!full_reg) begin
					wptr_next = wptr_reg + 1;
					empty_next = 0;
					if(wptr_next == rptr_reg) full_next = 1;
				end
			end
			// push/pop
			2'b11: begin
				if (full_reg) begin
					rptr_next = rptr_reg + 1;
					full_next = 0;
				end else if(empty_reg) begin
					wptr_next = wptr_reg + 1;
					empty_next = 0;
				end else begin
					wptr_next = wptr_reg + 1;
					rptr_next = rptr_reg + 1;
				end
			end
		endcase
	end
endmodule
