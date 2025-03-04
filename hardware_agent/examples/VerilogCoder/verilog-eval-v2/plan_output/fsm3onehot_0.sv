`timescale 1 ps/1 ps
`define OK 12
`define INCORRECT 13


module stimulus_gen (
	input clk,
	output logic in,
	output logic [3:0] state,
	input tb_match
);

	int errored1 = 0;
	int onehot_error = 0;
	
	initial begin
		// Test the one-hot cases first.
		repeat(200) @(posedge clk, negedge clk) begin
			state <= 1<< ($unsigned($random) % 4);
			in <= $random;
			if (!tb_match) onehot_error++;
		end
			
			
		// Random.
		errored1 = 0;
		repeat(400) @(posedge clk, negedge clk) begin
			state <= $random;
			in <= $random;
			if (!tb_match)
				errored1++;
		end
		if (!onehot_error && errored1) 
			$display ("Hint: Your circuit passed when given only one-hot inputs, but not with random inputs.");

		if (!onehot_error && errored1)
			$display("Hint: Are you doing something more complicated than deriving state transition equations by inspection?\n");

		#1 $finish;
	end
	
endmodule

module tb();

	typedef struct packed {
		int errors;
		int errortime;
		int errors_next_state;
		int errortime_next_state;
		int errors_out;
		int errortime_out;

		int clocks;
	} stats;
	
	stats stats1;
	
	
	wire[511:0] wavedrom_title;
	wire wavedrom_enable;
	int wavedrom_hide_after_time;
	
	reg clk=0;
	initial forever
		#5 clk = ~clk;

	logic in;
	logic [3:0] state;
	logic [3:0] next_state_ref;
	logic [3:0] next_state_dut;
	logic out_ref;
	logic out_dut;

	initial begin 
		$dumpfile("wave.vcd");
		$dumpvars();
	end


	wire tb_match;		// Verification
	wire tb_mismatch = ~tb_match;
	
	stimulus_gen stim1 (
		.clk,
		.* ,
		.in,
		.state );
	RefModule good1 (
		.in,
		.state,
		.next_state(next_state_ref),
		.out(out_ref) );
		
	TopModule top_module1 (
		.in,
		.state,
		.next_state(next_state_dut),
		.out(out_dut) );

	
	bit strobe = 0;
	task wait_for_end_of_timestep;
		repeat(5) begin
			strobe <= !strobe;  // Try to delay until the very end of the time step.
			@(strobe);
		end
	endtask	

	
	final begin
		if (stats1.errors_next_state) $display("Hint: Output '%s' has %0d mismatches. First mismatch occurred at time %0d.", "next_state", stats1.errors_next_state, stats1.errortime_next_state);
		else $display("Hint: Output '%s' has no mismatches.", "next_state");
		if (stats1.errors_out) $display("Hint: Output '%s' has %0d mismatches. First mismatch occurred at time %0d.", "out", stats1.errors_out, stats1.errortime_out);
		else $display("Hint: Output '%s' has no mismatches.", "out");

		$display("Hint: Total mismatched samples is %1d out of %1d samples\n", stats1.errors, stats1.clocks);
		$display("Simulation finished at %0d ps", $time);
		$display("Mismatches: %1d in %1d samples", stats1.errors, stats1.clocks);
	end
	
	// Verification: XORs on the right makes any X in good_vector match anything, but X in dut_vector will only match X.
	assign tb_match = ( { next_state_ref, out_ref } === ( { next_state_ref, out_ref } ^ { next_state_dut, out_dut } ^ { next_state_ref, out_ref } ) );
	// Use explicit sensitivity list here. @(*) causes NetProc::nex_input() to be called when trying to compute
	// the sensitivity list of the @(strobe) process, which isn't implemented.
	always @(posedge clk, negedge clk) begin

		stats1.clocks++;
		if (!tb_match) begin
			if (stats1.errors == 0) stats1.errortime = $time;
			stats1.errors++;
		end
		if (next_state_ref !== ( next_state_ref ^ next_state_dut ^ next_state_ref ))
		begin if (stats1.errors_next_state == 0) stats1.errortime_next_state = $time;
			stats1.errors_next_state = stats1.errors_next_state+1'b1; end
		if (out_ref !== ( out_ref ^ out_dut ^ out_ref ))
		begin if (stats1.errors_out == 0) stats1.errortime_out = $time;
			stats1.errors_out = stats1.errors_out+1'b1; end

	end

   // add timeout after 100K cycles
   initial begin
     #1000000
     $display("TIMEOUT");
     $finish();
   end

endmodule



module RefModule (
  input in,
  input [3:0] state,
  output reg [3:0] next_state,
  output out
);

  parameter A=0, B=1, C=2, D=3;

  assign next_state[A] = (state[A] | state[C]) & ~in;
  assign next_state[B] = (state[A] | state[B] | state[D]) & in;
  assign next_state[C] = (state[B] | state[D]) & ~in;
  assign next_state[D] = state[C] & in;

  assign out = (state[D]);

endmodule


module TopModule
(
  input  logic       in,
  input  logic [3:0] state,
  output logic [3:0] next_state,
  output logic       out
);

  // State encoding
  localparam A = 4'b0001;
  localparam B = 4'b0010;
  localparam C = 4'b0100;
  localparam D = 4'b1000;

  // Combinational logic for next state when 'in' is 0
  always @(*) begin
    if (in == 1'b0) begin
      next_state = 4'b0000;
      if (state[0] == 1'b1) // State A
        next_state[0] = 1'b1; // Next state is A
      if (state[1] == 1'b1) // State B
        next_state[2] = 1'b1; // Next state is C
      if (state[2] == 1'b1) // State C
        next_state[0] = 1'b1; // Next state is A
      if (state[3] == 1'b1) // State D
        next_state[2] = 1'b1; // Next state is C
    end
    else if (in == 1'b1) begin
      next_state = 4'b0000;
      if (state[0] == 1'b1) // State A
        next_state[1] = 1'b1; // Next state is B
      if (state[1] == 1'b1) // State B
        next_state[1] = 1'b1; // Next state is B
      if (state[2] == 1'b1) // State C
        next_state[3] = 1'b1; // Next state is D
      if (state[3] == 1'b1) // State D
        next_state[1] = 1'b1; // Next state is B
    end
  end

  // Combinational logic for output
  always @(*) begin
    out = 1'b0;
    if (state[3] == 1'b1) // State D
      out = 1'b1; // Output is 1
  end

endmodule