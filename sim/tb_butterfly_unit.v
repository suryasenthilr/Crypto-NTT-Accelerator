`timescale 1ns / 1ps

module tb_butterfly_unit;

    reg        clk;
    reg        rst_n;
    reg        mode_kyber;
    reg        is_gs;
    reg [23:0] u_in;
    reg [23:0] v_in;
    reg [23:0] twiddle;
    wire [23:0] u_out;
    wire [23:0] v_out;

    ntt_butterfly_unit dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode_kyber(mode_kyber),
        .is_gs(is_gs),
        .u_in(u_in),
        .v_in(v_in),
        .twiddle(twiddle),
        .u_out(u_out),
        .v_out(v_out)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        mode_kyber = 0;
        is_gs = 0;
        u_in = 0;
        v_in = 0;
        twiddle = 0;

        #20;
        rst_n = 1;
        #10;

        // -------------------------------------------------------------
        // Test 1: Dilithium Cooley-Tukey (CT)
        // u = 100, v = 50, twiddle = 2
        // t = (50 * 2) mod 8380417 = 100
        // u' = (100 + 100) = 200
        // v' = (100 - 100) = 0
        // Butterfly has 3 cycles latency
        // -------------------------------------------------------------
        $display("[TEST] Testing Dilithium CT Butterfly...");
        mode_kyber = 0; is_gs = 0;
        @(negedge clk);
        u_in = 24'd100; v_in = 24'd50; twiddle = 24'd2;
        @(negedge clk);
        u_in = 0; v_in = 0; twiddle = 0;
        @(negedge clk);
        @(negedge clk);
        $display("T=%0t: After 3 cycles: u_out=%d, v_out=%d", $time, u_out, v_out);
        if (u_out !== 24'd200 || v_out !== 24'd0) begin
            $display("[FAIL] Dilithium CT: Got u=%d, v=%d (Expected 200, 0)", u_out, v_out);
            $finish;
        end
        $display("[PASS] Dilithium CT Verified!");

        // -------------------------------------------------------------
        // Test 2: Dilithium Gentleman-Sande (GS)
        // u = 200, v = 0, twiddle = 2
        // u' = (u + v) = 200
        // v' = ((u - v) * twiddle) = (200 * 2) = 400
        // -------------------------------------------------------------
        $display("[TEST] Testing Dilithium GS Butterfly...");
        mode_kyber = 0; is_gs = 1;
        @(negedge clk);
        u_in = 24'd200; v_in = 24'd0; twiddle = 24'd2;
        @(negedge clk);
        u_in = 0; v_in = 0; twiddle = 0;
        @(negedge clk);
        @(negedge clk);
        $display("T=%0t: After 3 cycles GS: u_out=%d, v_out=%d", $time, u_out, v_out);
        if (u_out !== 24'd200 || v_out !== 24'd400) begin
            $display("[FAIL] Dilithium GS: Got u=%d, v=%d (Expected 200, 400)", u_out, v_out);
            $finish;
        end
        $display("[PASS] Dilithium GS Verified!");

        $display("[PASS] All Butterfly Unit Tests Passed Successfully!");
        $finish;
    end

endmodule
