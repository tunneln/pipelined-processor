`timescale 1ps/1ps

`define MOV 0
`define ADD 1
`define JMP 2
`define HLT 3
`define LD  4
`define LDR 5
`define JEQ 6
`define ST  7

module main();

	initial begin
		$dumpfile("cpu.vcd");
		$dumpvars(0, main);
		inst_cache[0][31:16] = 16'hffff;
		inst_cache[1][31:16] = 16'hffff;
		inst_cache[2][31:16] = 16'hffff;
		inst_cache[3][31:16] = 16'hffff;
		inst_cache[4][31:16] = 16'hffff;
		inst_cache[5][31:16] = 16'hffff;
		inst_cache[6][31:16] = 16'hffff;
	end

	// clock
	wire clk;
	clock c0(clk);

	// halt logic
	reg halt = 0;
	wire  W_v = wen | wen_mem | r_jmp | x_jeq;
	wire [15:0] cycle;
	counter ctr((halt == 1), clk, W_v, cycle);

	// PC maintainers
	reg [15:0] curr_pc = 16'h0000;
	reg [1:0] curr_count = 2;
	reg [15:0] correct_curr_pc;


	////////				////////				////////
	// F0 //				// F0 //				// F0 //
	////////				////////				////////

	reg [15:0] f_inst;
	reg [15:0] f_pc;
	reg f_v = 1;

	reg [15:0] pc = 16'h0000;
	reg [15:0] memIn;
	wire [15:0] inst;
	wire [15:0] memOut;

	reg [31:0] inst_cache [6:0];
	reg [2:0] inst_cache_c = 0;
	wire [2:0] cache_hit = (inst_cache[0][31:16] == curr_pc) ? 0 : (inst_cache[1][31:16] == curr_pc) ? 1 :
			(inst_cache[2][31:16] == curr_pc) ? 2 : (inst_cache[3][31:16] == curr_pc) ? 3 :
			(inst_cache[4][31:16] == curr_pc) ? 4 : (inst_cache[5][31:16] == curr_pc) ? 5 :
			(inst_cache[6][31:16] == curr_pc) ? 6 : 7;
	wire valid = inst[15:0] !== 16'hxxxx;

	reg [1:0] stall_c = 2;
	wire conflict = d_inst[3:0] == inst[11:8] & (d_inst[15:12] == `MOV | d_inst[15:12] == `ADD
			| d_inst[15:12] == `LD | d_inst[15:12] == `LDR);
	wire stall = valid & inst[15:12] == `ST & (curr_pc == inst[7:0] - 1 | curr_pc == inst[7:0] - 2) &
			~conflict | stall_c == 1;

	reg wen_delay;
	wire wen_mem = wen_delay;
	reg [15:0] waddr_mem;
	reg [15:0] wdata_mem;

	mem i0(clk, pc, inst, memIn, memOut, wen_mem, waddr_mem, wdata_mem);

	always @(posedge clk) begin
		if (f_v) begin
			if (curr_count == 0 & ~d_stall) curr_count <= 2;
			else if (r_stall && curr_count != 0) curr_count <= curr_count - 2;
			else if (d_stall && curr_count != 0) curr_count <= curr_count - 1;

			if (stall & stall_c != 0) stall_c <= stall_c - 1;

			if (r_stall & curr_count == 2) correct_curr_pc <= curr_pc - 1;
			else if (d_stall & curr_count == 2) correct_curr_pc <= curr_pc;
			else if (stall & stall_c == 2) correct_curr_pc <= inst[15:0];

			curr_pc <= (r_stall & curr_count == 2) ? curr_pc - 1 :
					((stall & stall_c != 0 | d_stall & curr_count != 0) | pc < 2) ? curr_pc :
					(x_jmp) ? x_inst[11:0] - 1 : (x_jeq) ? x_pc + x_inst[3:0] - 2 : curr_pc + 1;
			pc <= (stall & stall_c == 2) ? pc - 1 : (d_stall) ? curr_pc : (r_jmp & ~is_jeq) ?
					r_inst[11:0] : (x_jeq) ? x_pc + x_inst[3:0] : pc + 1;

			d_v <= (x_jmp | x_jeq | is_jmp | is_jeq) ? 0 : f_v;
			d_inst <= (pc > 3 & cache_hit != 7) ? inst_cache[cache_hit][15:0] :
					(r_stall & d_stall_c == 1) ? r_inst :
					(d_stall | is_jmp | is_jeq | stall) ? d_inst :
					(stall_c == 0) ? correct_curr_pc : inst;
			d_pc <= (r_stall & d_stall_c == 1) ? r_pc :
					(d_stall | stall) ? d_pc : curr_pc;

			if (stall_c == 0) begin
				stall_c <= 2;
				inst_cache[inst_cache_c][31:16] <= curr_pc;
				inst_cache[inst_cache_c][15:0] <= data1;
				inst_cache_c <= (inst_cache_c == 6) ? 0 : inst_cache_c + 1;
			end

			if (d_stall_c == 1)
				curr_pc <= correct_curr_pc;
		end

	end


	////////				////////				////////
	// D0 //				// D0 //				// D0 //
	////////				////////				////////

	reg [15:0] d_inst;
	reg [15:0] d_pc;
	reg d_v = 0;

	wire isMov = (d_inst[15:12] == `MOV);
	wire isAdd = (d_inst[15:12] == `ADD);
	wire isLdr = (d_inst[15:12] == `LDR);
	wire isLd  = (d_inst[15:12] == `LD);
	wire isJeq = (d_inst[15:12] == `JEQ);
	wire isSt  = (d_inst[15:12] == `ST);

	wire d_valid = (d_inst[15:12] < 8 && d_inst[15:12] !== 4'bxxxx);

	reg [15:0] d_busy = 0;
	reg [2:0] d_stall_c = 5;

	wire d_raIsBusy = d_busy[d_inst[11:8]] & (isLdr | isAdd | isJeq | isSt);
	wire d_rbIsBusy = d_busy[d_inst[7:4]] & (isLdr | isAdd | isJeq);

	reg d_past_stall = 0;
	wire d_stall = d_valid & (d_raIsBusy | d_rbIsBusy) & d_v & ~r_jmp & ~x_jmp & ~x_jeq ||
			(d_stall_c < 5 && d_stall_c > 0) | r_stall;
	wire d_doit = d_v & ~d_stall & ~x_jmp & ~is_jmp & ~x_jeq & ~is_jeq & ~r_stall;
	wire d_usesRt = (isMov | isAdd | isLdr | isLd);

	always @(posedge clk) begin

		if (d_v) begin
			if (d_stall & d_stall_c > 0)
				d_stall_c <= (d_stall_c == 5 & r_stall) ? d_stall_c - 2 : d_stall_c - 1;

			if (d_stall_c == 1)
				d_past_stall <= 1;
			else if (d_stall_c == 0)
				d_stall_c <= 5;

			if (d_stall & isSt & wb_inst[3:0] == d_inst[11:8]) begin
				inst_cache[inst_cache_c][31:16] <= d_inst[7:0];
				inst_cache[inst_cache_c][15:0] <= (wb_inst[15:12] == `ADD | wb_inst[15:12] == `MOV)
							? wb_xval : (wb_inst[15:12] == `LD | wb_inst[15:12] == `LDR) ? memOut :
							inst_cache[inst_cache_c][15:0];
				inst_cache_c <= (inst_cache_c == 6) ? 0 : inst_cache_c + 1;
			end

			r_inst <= (d_stall | is_jmp | is_jeq | stall) ? r_inst : d_inst;
			r_pc <= (d_stall) ? r_pc : d_pc;

			if (d_usesRt & d_doit) begin
				d_busy[d_inst[3:0]] <= 1;
				if (d_inst[3:0] != wb_inst[3:0] && wb_en)
					d_busy[wb_inst[3:0]] <= 0;
			end else if (wb_en)
				d_busy[wb_inst[3:0]] <= 0;

			if (r_inst[15:12] == `ST & d_doit) begin
				r_mbusy[r_inst[7:0]] <= 1;
				if (r_inst[7:0] != wb_inst[7:0] && wb_men)
					r_mbusy[wb_inst[7:0]] <= 0;
			end else if (wb_men)
				r_mbusy[wb_inst[7:0]] <= 0;

			if (x_jmp | x_jeq) begin
				d_busy <= 0;
				r_mbusy <= 0;
			end

			if (~d_valid) r_v <= 0;
			else r_v <= (x_jmp | x_jeq) ? 0 : d_v;
		end

		if (wen & ren0 & waddr == raddr0 & (d_stall_c == 1 | d_stall_c == 5)) begin
			rdata0_fix[27:27] <= 1'b1;
			rdata0_fix[26:16] <= (d_stall_c == 1) ? d_pc : curr_pc;
			rdata0_fix[15:0] <= wdata;
		end
		if (wen & ren1 & waddr == raddr1 & (d_stall_c == 1 | d_stall_c == 5)) begin
			rdata1_fix[27:27] <= 1'b1;
			rdata1_fix[26:16] <= (d_stall_c == 1) ? d_pc : curr_pc;
			rdata1_fix[15:0] <= wdata;
		end

	end


	////////				////////				////////
	// R0 //				// R0 //				// R0 //
	////////				////////				////////

	reg [15:0] r_prev_pc;
	reg [15:0] r_inst;
	reg [15:0] r_pc;
	reg r_v = 0;

	wire r_jmp = r_v & r_inst[15:12] == `JMP && r_valid &&
				r_inst[11:0] != r_pc + 1 && ~x_jmp & ~x_jeq & ~is_jeq & ~d_stall;

	wire [3:0] raddr0 = (d_stall_c == 1) ? d_inst[7:4] : inst[7:4];
	wire [3:0] raddr1 = (d_stall_c == 1) ? d_inst[11:8] : inst[11:8];

	wire [15:0] rdata0;
	wire [15:0] rdata1;
	reg [27:0] rdata0_fix;
	reg [27:0] rdata1_fix;
	wire [15:0] data0 = (rdata0_fix[27:27] !== 1'bx & rdata0_fix[27:27] & d_stall_c == 5) ?
			rdata0_fix[15:0] : rdata0;
	wire [15:0] data1 = (rdata1_fix[27:27] !== 1'bx & rdata1_fix[27:27] & d_stall_c == 5) ?
			rdata1_fix[15:0] : rdata1;

	wire [3:0] waddr = wb_inst[3:0];
	wire [15:0] wdata = (wb_inst[15:12] == `LD | wb_inst[15:12] == `LDR) ?
			memOut : (wb_v & wb_inst[15:12] == `ADD) ? wb_xval : wb_inst[11:4];

	wire r_valid = r_inst[15:12] !== 4'bxxxx;
	wire using_reg = (d_stall_c == 1) ?
			(d_inst[15:12] == `ADD | d_inst[15:12] == `LDR | d_inst[15:12] == `JEQ | d_inst[15:12] == `ST) :
			(inst[15:12] == `ADD | inst[15:12] == `LDR | inst[15:12] == `JEQ | inst[15:12] == `ST) & ~d_stall;
	wire ren0 = valid & using_reg & (d_stall_c == 1 & d_inst[15:12] != `ST | d_stall_c != 1 & inst[15:12] != `ST);
	wire ren1 = valid & using_reg;

	wire wen = wb_v & wb_en & (~d_past_stall || d_stall_c == 1) &
			(wb_valid && wb_inst[15:12] != `HLT);

	regs r0(clk, ren0, raddr0, rdata0, ren1, raddr1, rdata1, wen, waddr, wdata);

	reg still_stall = 0;
	reg [255:0] r_mbusy = 0;
	wire r_mabIsBusy = data0 !== 16'hxxxx & data1 !== 16'hxxxx &
			r_mbusy[data0 + data1] & (r_inst[15:12] == `LDR);
	wire r_miIsBusy = r_mbusy[r_inst[11:4]] & (r_inst[15:12] == `LD);
	wire r_stall = r_valid & r_v & (r_mabIsBusy | r_miIsBusy);

	always @(posedge clk) begin

		if (r_v) begin
			if (r_stall)
				still_stall <= 1;
			if (~d_stall)
				still_stall <= 0;
			x_inst <= ((r_stall | still_stall)) ? x_inst : r_inst;
			x_v <= (x_jmp | x_jeq) ? 0 : r_v;
			x_pc <= (r_stall | still_stall) ? x_pc : r_pc;
			x_data0 <= data0;
			x_data1 <= data1;

			if (r_inst[15:12] == `ST & ~d_stall) begin
				inst_cache[inst_cache_c][31:16] <= r_inst[7:0];
				inst_cache[inst_cache_c][15:0] <= data1;
				inst_cache_c <= (inst_cache_c == 6) ? 0 : inst_cache_c + 1;
			end

			if (rdata0_fix[27:27] & rdata0_fix[26:16] == r_pc)
				rdata0_fix[27:27] <= 1'b0;
			if (rdata1_fix[27:27] & rdata1_fix[26:16] == r_pc)
				rdata1_fix[27:27] <= 1'b0;
		end

	end


	////////				////////				////////
	// X0 //				// X0 //				// X0 //
	////////				////////				////////

	reg [15:0] x_inst;
	reg [15:0] x_pc;
	reg x_v = 0;

	reg [15:0] x_data0;
	reg [15:0] x_data1;

	wire x_valid = x_inst[15:12] !== 4'bxxxx;
	wire x_jmp = x_v & x_valid & (x_inst[15:12] == `JMP && x_inst[11:0] != x_pc + 1);
	wire x_jeq = x_v & x_valid & x_inst[15:12] == `JEQ && x_inst[3:0] != 1 & x_data0 == x_data1;

	reg [11:0] jmp_pc;
	reg [11:0] jeq_pc;
	reg is_jmp = 0;
	reg is_jeq = 0;

	always @(posedge clk) begin

		if (x_v) begin
			m0_inst <= x_inst;
			m0_v <= x_v;
			m0_pc <= x_pc;

			if (x_jeq) begin
				jeq_pc <= x_pc;
				is_jeq <= 1;
			end else if (x_jmp) begin
				jmp_pc <= x_pc;
				is_jmp <= 1;
			end else if (x_inst[15:12] == `MOV)
				m0_xval <= x_inst[11:4];
			else if (x_inst[15:12] == `LD)
				memIn <= x_inst[11:4];
			else if (x_inst[15:12] == `LDR)
				memIn <= x_data0 + x_data1;
			else if (x_inst[15:12] == `ADD)
				m0_xval <= x_data0 + x_data1;
			else if (x_inst[15:12] == `ST)
				m0_xval <= x_data1;
		end

	end


	////////				////////				////////
	// M0 //				// M0 //				// M0 //
	////////				////////				////////

	reg [15:0] m0_inst;
	reg [15:0] m0_pc;
	reg [15:0] m0_xval;
	reg m0_v = 0;

	always @(posedge clk) begin

		if (m0_v) begin
			m1_inst <= m0_inst;
			m1_v <= m0_v;
			m1_pc <= m0_pc;
			m1_xval <= m0_xval;

			if (jmp_pc == m0_pc) is_jmp <= 0;
		end

	end


	////////				////////				////////
	// M1 //				// M1 //				// M1 //
	////////				////////				////////

	reg [15:0] m1_inst;
	reg [15:0] m1_pc;
	reg [15:0] m1_xval;
	reg m1_v = 0;

	always @(posedge clk) begin

		if (m1_v) begin
			wb_inst <= m1_inst;
			wb_v <= m1_v;
			wb_pc <= m1_pc;
			wb_xval <= m1_xval;

			if (jeq_pc == m1_pc) is_jeq <= 0;
		end

	end


	////////				////////				////////
	// WB //				// WB //				// WB //
	////////				////////				////////

	reg [15:0] wb_inst;
	reg [15:0] wb_pc;
	reg [15:0] wb_xval;
	reg wb_v = 0;

	wire wb_valid = wb_inst[15:12] !== 4'bxxxx;
	wire wb_en = wb_valid  && wb_inst[15:12] != `JMP && wb_inst[15:12] != `JEQ &&
					wb_inst[15:12] != `HLT && wb_inst[15:12] != `ST;
	wire wb_men = wb_inst[15:12] == `ST & (~r_stall | ~(d_stall_c > 1 & d_stall_c < 6));

	always @(posedge clk) begin

		wen_delay <= wb_inst[15:12] == `ST & wb_inst[15:12] != `HLT & wb_v &
				(~d_past_stall | d_stall_c == 1) & wb_valid;
		waddr_mem <= wb_inst[7:0];
		wdata_mem <= wb_xval;

		if (wb_pc != m1_pc)
			d_past_stall <= 0;

		if (wb_v) begin
			if (wb_inst[15:12] == `HLT)
				halt <= 1;

			if (wb_men) begin
				if (inst_cache[0][31:16] == wb_pc) inst_cache[0][31:16] <= 16'hffff;
				if (inst_cache[1][31:16] == wb_pc) inst_cache[1][31:16] <= 16'hffff;
				if (inst_cache[2][31:16] == wb_pc) inst_cache[2][31:16] <= 16'hffff;
				if (inst_cache[3][31:16] == wb_pc) inst_cache[3][31:16] <= 16'hffff;
				if (inst_cache[4][31:16] == wb_pc) inst_cache[4][31:16] <= 16'hffff;
				if (inst_cache[5][31:16] == wb_pc) inst_cache[5][31:16] <= 16'hffff;
				if (inst_cache[6][31:16] == wb_pc) inst_cache[6][31:16] <= 16'hffff;
			end

		end

	end

endmodule
