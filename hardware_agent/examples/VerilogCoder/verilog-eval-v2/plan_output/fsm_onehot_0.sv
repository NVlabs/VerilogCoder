`timescale 1 ps/1 ps
`define OK 12
`define INCORRECT 13


module stimulus_gen (
	input clk,
	output logic in,
	output logic [9:0] state,
	input tb_match,
	input [9:0] next_state_ref,
	input [9:0] next_state_dut,
	output reg[511:0] wavedrom_title,
	output reg wavedrom_enable	
);


// Add two ports to module stimulus_gen:
//    output [511:0] wavedrom_title
//    output reg wavedrom_enable

	task wavedrom_start(input[511:0] title = "");
	endtask
	
	task wavedrom_stop;
		#1;
	endtask	



	int errored1 = 0;
	int errored2 = 0;
	int onehot_error = 0;
	reg [9:0] state_error = 10'h0;
	
	initial begin
		repeat(2) @(posedge clk);
		forever @(posedge clk, negedge clk)
			state_error <= state_error | (next_state_ref^next_state_dut);
	end
		
	initial begin
		state <= 0;
		
		@(negedge clk) wavedrom_start();
		for (int i=0;i<10;i++) begin
			@(negedge clk, posedge clk);
			state <= 1<< i;
			in <= 0;
		end
		for (int i=0;i<10;i++) begin
			@(negedge clk, posedge clk);
			state <= 1<< i;
			in <= 1;
		end			
		@(negedge clk) wavedrom_stop();
		
		// Test the one-hot cases first.
		repeat(200) @(posedge clk, negedge clk) begin
			state <= 1<< ($unsigned($random) % 10);
			in <= $random;
			if (!tb_match) onehot_error++;
		end
		
		// Two-hot.
		errored1 = 0;
		repeat(400) @(posedge clk, negedge clk) begin
			state <= (1<< ($unsigned($random) % 10)) | (1<< ($unsigned($random) % 10));
			in <= $random;
			if (!tb_match)
				errored1++;
		end
		
		if (!onehot_error && errored1) 
			$display ("Hint: Your circuit passed when given only one-hot inputs, but not with two-hot inputs.");
		
		// Random.
		errored2 = 0;
		repeat(800) @(posedge clk, negedge clk) begin
			state <= $random;
			in <= $random;
			if (!tb_match)
				errored2++;
		end
		if (!onehot_error && errored2) 
			$display ("Hint: Your circuit passed when given only one-hot inputs, but not with random inputs.");

		if (!onehot_error && (errored1 || errored2))
			$display("Hint: Are you doing something more complicated than deriving state transition equations by inspection?\n");
		
		for (int i=0;i<$bits(state_error);i++)
			$display("Hint: next_state[%0d] is %s.", i, (state_error[i] === 1'b0) ? "correct": "incorrect");

		#1 $finish;
	end
	
endmodule

module tb();

	typedef struct packed {
		int errors;
		int errortime;
		int errors_next_state;
		int errortime_next_state;
		int errors_out1;
		int errortime_out1;
		int errors_out2;
		int errortime_out2;

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
	logic [9:0] state;
	logic [9:0] next_state_ref;
	logic [9:0] next_state_dut;
	logic out1_ref;
	logic out1_dut;
	logic out2_ref;
	logic out2_dut;

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
		.out1(out1_ref),
		.out2(out2_ref) );
		
	TopModule top_module1 (
		.in,
		.state,
		.next_state(next_state_dut),
		.out1(out1_dut),
		.out2(out2_dut) );

	
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
		if (stats1.errors_out1) $display("Hint: Output '%s' has %0d mismatches. First mismatch occurred at time %0d.", "out1", stats1.errors_out1, stats1.errortime_out1);
		else $display("Hint: Output '%s' has no mismatches.", "out1");
		if (stats1.errors_out2) $display("Hint: Output '%s' has %0d mismatches. First mismatch occurred at time %0d.", "out2", stats1.errors_out2, stats1.errortime_out2);
		else $display("Hint: Output '%s' has no mismatches.", "out2");

		$display("Hint: Total mismatched samples is %1d out of %1d samples\n", stats1.errors, stats1.clocks);
		$display("Simulation finished at %0d ps", $time);
		$display("Mismatches: %1d in %1d samples", stats1.errors, stats1.clocks);
	end
	
	// Verification: XORs on the right makes any X in good_vector match anything, but X in dut_vector will only match X.
	assign tb_match = ( { next_state_ref, out1_ref, out2_ref } === ( { next_state_ref, out1_ref, out2_ref } ^ { next_state_dut, out1_dut, out2_dut } ^ { next_state_ref, out1_ref, out2_ref } ) );
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
		if (out1_ref !== ( out1_ref ^ out1_dut ^ out1_ref ))
		begin if (stats1.errors_out1 == 0) stats1.errortime_out1 = $time;
			stats1.errors_out1 = stats1.errors_out1+1'b1; end
		if (out2_ref !== ( out2_ref ^ out2_dut ^ out2_ref ))
		begin if (stats1.errors_out2 == 0) stats1.errortime_out2 = $time;
			stats1.errors_out2 = stats1.errors_out2+1'b1; end

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
  input [9:0] state,
  output [9:0] next_state,
  output out1,
  output out2
);

  assign out1 = state[8] | state[9];
  assign out2 = state[7] | state[9];

  assign next_state[0] = !in && (|state[4:0] | state[7] | state[8] | state[9]);
  assign next_state[1] = in && (state[0] | state[8] | state[9]);
  assign next_state[2] = in && state[1];
  assign next_state[3] = in && state[2];
  assign next_state[4] = in && state[3];
  assign next_state[5] = in && state[4];
  assign next_state[6] = in && state[5];
  assign next_state[7] = in && (state[6] | state[7]);
  assign next_state[8] = !in && state[5];
  assign next_state[9] = !in && state[6];

endmodule


module TopModule (
    input  logic      in,
    input  logic [9:0] state,
    output logic [9:0] next_state,
    output logic      out1,
    output logic      out2
);

    // Local signals for intermediate calculations
    logic [9:0] next_state_comb;

    // Combinational logic for next state
    always @(*) begin
        // Default assignment for next state
        next_state_comb = 10'b0;

        // State transitions for S0
        if (state[0]) begin
            next_state_comb[0] = ~in;
            next_state_comb[1] = in;
        end
        
        // State transitions for S1
        if (state[1]) begin
            next_state_comb[0] = ~in;
            next_state_comb[2] = in;
        end
        
        // State transitions for S2
        if (state[2]) begin
            next_state_comb[0] = ~in;
            next_state_comb[3] = in;
        end
        
        // State transitions for S3
        if (state[3]) begin
            next_state_comb[0] = ~in;
            next_state_comb[4] = in;
        end
        
        // State transitions for S4
        if (state[4]) begin
            next_state_comb[0] = ~in;
            next_state_comb[5] = in;
        end
        
        // State transitions for S5
        if (state[5]) begin
            next_state_comb[8] = ~in;
            next_state_comb[6] = in;
        end
        
        // State transitions for S6
        if (state[6]) begin
            next_state_comb[9] = ~in;
            next_state_comb[7] = in;
        end
        
        // State transitions for S7
        if (state[7]) begin
            next_state_comb[0] = ~in;
            next_state_comb[7] = in;
        end
        
        // State transitions for S8
        if (state[8]) begin
            next_state_comb[0] = ~in;
            next_state_comb[1] = in;
        end
        
        // State transitions for S9
        if (state[9]) begin
            next_state_comb[0] = ~in;
            next_state_comb[1] = in;
        end
    end

    // Assign the combinational result to the output
    assign next_state = next_state_comb;

    // Combinational logic for outputs
    always @(*) begin
        // Output logic for out1 and out2
        out1 = state[8] | state[9];
        out2 = state[7] | state[9];
    end

endmodule