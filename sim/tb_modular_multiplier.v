`timescale 1ns / 1ps

module tb_modular_multiplier;

    reg        clk;
    reg        rst_n;
    reg        mode_kyber;
    reg [23:0] in_a;
    reg [23:0] in_b;
    wire [23:0] out_p;

    modular_multiplier dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode_kyber(mode_kyber),
        .in_a(in_a),
        .in_b(in_b),
        .out_p(out_p)
    );

    always #5 clk = ~clk; // 100MHz clock

    integer i;
    integer pass_count;
    reg [23:0] expected;

    initial begin
        clk = 0;
        rst_n = 0;
        mode_kyber = 0;
        in_a = 0;
        in_b = 0;
        pass_count = 0;

        #20;
        rst_n = 1;
        #10;

        // -------------------------------------------------------------
        // Test 1: Dilithium Mode (mode_kyber = 0)
        // -------------------------------------------------------------
        $display("[TEST] Starting Dilithium Mode Verification...");
        mode_kyber = 0;

        // Vector 1: 1000 * 2000 mod 8380417 = 2000000
        in_a = 24'd1000; in_b = 24'd2000;
        @(posedge clk);
        @(posedge clk);
        #1;
        if (out_p !== 24'd2000000) begin
            $display("[FAIL] Dilithium 1000*2000: Got %d, Expected 2000000", out_p);
            $finish;
        end else pass_count = pass_count + 1;

        // Vector 2: 8380416 * 8380416 mod 8380417 = 1 ((-1)*(-1) = 1)
        in_a = 24'd8380416; in_b = 24'd8380416;
        @(posedge clk);
        @(posedge clk);
        #1;
        if (out_p !== 24'd1) begin
            $display("[FAIL] Dilithium (-1)*(-1): Got %d, Expected 1", out_p);
            $finish;
        end else pass_count = pass_count + 1;

        // Vector 3: 4190208 * 2 mod 8380417 = 8380416
        in_a = 24'd4190208; in_b = 24'd2;
        @(posedge clk);
        @(posedge clk);
        #1;
        if (out_p !== 24'd8380416) begin
            $display("[FAIL] Dilithium 4190208*2: Got %d, Expected 8380416", out_p);
            $finish;
        end else pass_count = pass_count + 1;

        $display("[PASS] Dilithium Deterministic Vectors Verified!");

        // -------------------------------------------------------------
        // Test 2: Kyber Mode (mode_kyber = 1) - Montgomery domain twiddles
        // -------------------------------------------------------------
        $display("[TEST] Starting Kyber Mode Verification...");
        mode_kyber = 1;

        // Vector 1: a = 100, omega = 17, omega_mont = (17 * 65536) mod 3329 = 2226
        // Expected out = (100 * 17) mod 3329 = 1700
        in_a = 24'd100; in_b = 24'd2226;
        @(posedge clk);
        @(posedge clk);
        #1;
        if (out_p !== 24'd1700) begin
            $display("[FAIL] Kyber 100*17: Got %d, Expected 1700", out_p);
            $finish;
        end else pass_count = pass_count + 1;

        // Vector 2: a = 3328 (-1), omega = 3328 (-1), omega_mont = (3328 * 65536) mod 3329 = 1044
        // Expected out = ((-1) * (-1)) mod 3329 = 1
        in_a = 24'd3328; in_b = 24'd1044;
        @(posedge clk);
        @(posedge clk);
        #1;
        if (out_p !== 24'd1) begin
            $display("[FAIL] Kyber (-1)*(-1): Got %d, Expected 1", out_p);
            $finish;
        end else pass_count = pass_count + 1;

        $display("[PASS] All Modular Multiplier Unit Tests Passed Successfully!");
        $finish;
    end

endmodule
