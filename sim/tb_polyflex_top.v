`timescale 1ns / 1ps

module tb_polyflex_top;

    reg        clk;
    reg        rst_n;
    reg        mode_kyber;
    reg        is_gs;
    reg        start;
    wire       busy;
    wire       done;

    reg        host_we;
    reg [7:0]  host_addr;
    reg [23:0] host_wdata;
    wire [23:0] host_rdata;

    polyflex_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode_kyber(mode_kyber),
        .is_gs(is_gs),
        .start(start),
        .busy(busy),
        .done(done),
        .host_we(host_we),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_rdata(host_rdata)
    );

    always #5 clk = ~clk; // 100MHz clock

    integer i;
    integer errors;

    initial begin
        $dumpfile("sim/polyflex_top.vcd");
        $dumpvars(0, tb_polyflex_top);

        clk = 0;
        rst_n = 0;
        mode_kyber = 0;
        is_gs = 0;
        start = 0;
        host_we = 0;
        host_addr = 0;
        host_wdata = 0;
        errors = 0;

        #20;
        rst_n = 1;
        #20;

        // ====================================================================
        // Test 1: Dilithium (FIPS 204) Forward NTT
        // ====================================================================
        $display("\n=======================================================");
        $display("[TEST] Starting PolyFlex-NTT Dilithium Forward NTT Test");
        $display("=======================================================");

        // Load simple impulse input: poly[0] = 1, all others = 0
        // Expected NTT: all coefficients equal to 1!
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            host_we = 1;
            host_addr = i[7:0];
            host_wdata = (i == 0) ? 24'd1 : 24'd0;
        end
        @(negedge clk);
        host_we = 0;

        // Trigger NTT
        @(negedge clk);
        mode_kyber = 0;
        is_gs = 0;
        start = 1;
        @(negedge clk);
        start = 0;

        // Wait for completion
        fork
            begin
                wait (done == 1);
                $display("[INFO] Dilithium NTT completed at time %0t!", $time);
            end
            begin
                while (!done) begin
                    @(posedge clk);
                    if (dut.u_addr_gen.raddr0 == 7'd127 && dut.u_addr_gen.raddr1 == 7'd127) begin
                        $display("Time %0t: Read pair 127: ren0=%b, ren1=%b, twiddle_addr=%d, bank_u=%b",
                                 $time, dut.ren0, dut.ren1, dut.u_addr_gen.twiddle_addr, dut.u_addr_gen.bank_u);
                    end
                    if (dut.u_butterfly.u_in != 0 || dut.u_butterfly.v_in != 0) begin
                        if ($time > 12800000) begin
                            $display("Time %0t: Butterfly inputs: u_in=%d, v_in=%d, twiddle=%d, is_read_u_from_bank1=%b",
                                     $time, dut.u_butterfly.u_in, dut.u_butterfly.v_in, dut.u_butterfly.twiddle, dut.ag_read_u_from_bank1);
                        end
                    end
                    if (dut.u_addr_gen.wen0 && dut.u_addr_gen.waddr0 == 7'd127) begin
                        $display("Time %0t: Write to addr 127: wen0=%b, wdata0=%d, wen1=%b, wdata1=%d, bank_u=%b",
                                 $time, dut.u_addr_gen.wen0, dut.wdata0, dut.u_addr_gen.wen1, dut.wdata1, dut.u_addr_gen.write_u_to_bank1);
                    end
                end
            end
        join

        // Read back and verify: each coefficient should be 1
        @(negedge clk);
        for (i = 0; i < 256; i = i + 1) begin
            host_addr = i[7:0];
            @(negedge clk); // Allow synchronous SRAM read
            #1;
            if (host_rdata !== 24'd1) begin
                $display("[FAIL] Dilithium Impulse NTT: Index %d = %d (Expected 1)", i, host_rdata);
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("[PASS] Dilithium Impulse Test Passed! All 256 points equal 1.");
        end else begin
            $display("[FAIL] Total errors: %d", errors);
            $finish;
        end

        $display("\n[PASS] All Top-Level Hardware Tests Passed Successfully!");
        $finish;
    end

endmodule
