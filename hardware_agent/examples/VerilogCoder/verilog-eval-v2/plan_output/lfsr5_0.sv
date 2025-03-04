`timescale 1 ps/1 ps
`define OK 12
`define INCORRECT 13


module stimulus_gen (
	input clk,
	output reg reset,
	output reg[511:0] wavedrom_title,
	output reg wavedrom_enable,
	input tb_match	
);

	task reset_test(input async=0);
		bit arfail, srfail, datafail;
	
		@(posedge clk);
		@(posedge clk) reset <= 0;
		repeat(3) @(posedge clk);
	
		@(negedge clk) begin datafail = !tb_match ; reset <= 1; end
		@(posedge clk) arfail = !tb_match;
		@(posedge clk) begin
			srfail = !tb_match;
			reset <= 0;
		end
		if (srfail)
			$display("Hint: Your reset doesn't seem to be working.");
		else if (arfail && (async || !datafail))
			$display("Hint: Your reset should be %0s, but doesn't appear to be.", async ? "asynchronous" : "synchronous");
		// Don't warn about synchronous reset if the half-cycle before is already wrong. It's more likely
		// a functionality error than the reset being implemented asynchronously.
	
	endtask


// Add two ports to module stimulus_gen:
//    output [511:0] wavedrom_title
//    output reg wavedrom_enable

	task wavedrom_start(input[511:0] title = "");
	endtask
	
	task wavedrom_stop;
		#1;
	endtask	


	
	initial begin
		reset <= 1;
		@(negedge clk);
		wavedrom_start();
			reset_test();
			repeat(8) @(posedge clk);
		@(negedge clk);
		wavedrom_stop();
		repeat(400) @(posedge clk, negedge clk) begin
			reset <= !($random & 31);
		end
		@(posedge clk) reset <= 1'b0;
		repeat(2000) @(posedge clk);
		reset <= 1'b1;
		repeat(5) @(posedge clk);
		#1 $finish;
	end
	
endmodule

module tb();

	typedef struct packed {
		int errors;
		int errortime;
		int errors_q;
		int errortime_q;

		int clocks;
	} stats;
	
	stats stats1;
	
	
	wire[511:0] wavedrom_title;
	wire wavedrom_enable;
	int wavedrom_hide_after_time;
	
	reg clk=0;
	initial forever
		#5 clk = ~clk;

	logic reset;
	logic [4:0] q_ref;
	logic [4:0] q_dut;

	initial begin 
		$dumpfile("wave.vcd");
		$dumpvars();
	end


	wire tb_match;		// Verification
	wire tb_mismatch = ~tb_match;
	
	stimulus_gen stim1 (
		.clk,
		.* ,
		.reset );
	RefModule good1 (
		.clk,
		.reset,
		.q(q_ref) );
		
	TopModule top_module1 (
		.clk,
		.reset,
		.q(q_dut) );

	
	bit strobe = 0;
	task wait_for_end_of_timestep;
		repeat(5) begin
			strobe <= !strobe;  // Try to delay until the very end of the time step.
			@(strobe);
		end
	endtask	

	
	final begin
		if (stats1.errors_q) $display("Hint: Output '%s' has %0d mismatches. First mismatch occurred at time %0d.", "q", stats1.errors_q, stats1.errortime_q);
		else $display("Hint: Output '%s' has no mismatches.", "q");

		$display("Hint: Total mismatched samples is %1d out of %1d samples\n", stats1.errors, stats1.clocks);
		$display("Simulation finished at %0d ps", $time);
		$display("Mismatches: %1d in %1d samples", stats1.errors, stats1.clocks);
	end
	
	// Verification: XORs on the right makes any X in good_vector match anything, but X in dut_vector will only match X.
	assign tb_match = ( { q_ref } === ( { q_ref } ^ { q_dut } ^ { q_ref } ) );
	// Use explicit sensitivity list here. @(*) causes NetProc::nex_input() to be called when trying to compute
	// the sensitivity list of the @(strobe) process, which isn't implemented.
	always @(posedge clk, negedge clk) begin

		stats1.clocks++;
		if (!tb_match) begin
			if (stats1.errors == 0) stats1.errortime = $time;
			stats1.errors++;
		end
		if (q_ref !== ( q_ref ^ q_dut ^ q_ref ))
		begin if (stats1.errors_q == 0) stats1.errortime_q = $time;
			stats1.errors_q = stats1.errors_q+1'b1; end

	end

   // add timeout after 100K cycles
   initial begin
     #1000000
     $display("TIMEOUT");
     $finish();
   end

endmodule



module RefModule (
  input clk,
  input reset,
  output reg [4:0] q
);

  logic [4:0] q_next;
  always @(q) begin
    q_next = q[4:1];
    q_next[4] = q[0];
    q_next[2] ^= q[0];
  end

  always @(posedge clk) begin
    if (reset)
      q <= 5'h1;
    else
      q <= q_next;
  end

endmodule


module TopModule (
  input  logic clk,
  input  logic reset,
  output logic [4:0] q
);

  always @(posedge clk) begin
    if (reset) begin
      q <= 5'b00001; // Set LFSR output to 1 when reset is active-high
    end else begin
      q[4] <= q[0] ^ 1'b0; // Implement LFSR functionality for q[4]
      q[2] <= q[0] ^ q[3]; // Implement LFSR functionality for q[2] with tap at position 3
      q[3] <= q[4];        // Shift functionality for q[3]
      q[1] <= q[2];        // Shift functionality for q[1]
      q[0] <= q[1];        // Shift functionality for q[0]
    end
  end

endmodule