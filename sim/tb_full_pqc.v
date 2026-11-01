`timescale 1ns / 1ps

module tb_full_pqc;

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

    always #5 clk = ~clk;

    reg [23:0] input_mem [0:255];
    reg [23:0] output_mem [0:255];
    integer i, file_out, status;

    initial begin
        clk = 0;
        rst_n = 0;
        start = 0;
        host_we = 0;
        host_addr = 0;
        host_wdata = 0;

        // Read test configuration
        // mode_kyber: +mode_kyber=1/0
        // is_gs: +is_gs=1/0
        if (!$value$plusargs("mode_kyber=%d", mode_kyber)) mode_kyber = 0;
        if (!$value$plusargs("is_gs=%d", is_gs)) is_gs = 0;

        // Read input coefficients from hex file
        $readmemh("sim/input_poly.hex", input_mem);

        #20;
        rst_n = 1;
        #20;

        // 1. Host Load
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            host_we = 1;
            host_addr = i[7:0];
            host_wdata = input_mem[i];
        end
        @(negedge clk);
        host_we = 0;

        // 2. Trigger Compute Engine
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;

        // 3. Wait for Done
        wait (done == 1);
        @(negedge clk);

        // 4. Host Readback
        for (i = 0; i < 256; i = i + 1) begin
            host_addr = i[7:0];
            @(negedge clk);
            output_mem[i] = host_rdata;
        end

        // 5. Write to output hex file
        file_out = $fopen("sim/output_poly.hex", "w");
        for (i = 0; i < 256; i = i + 1) begin
            $fdisplay(file_out, "%06x", output_mem[i]);
        end
        $fclose(file_out);

        $display("[SIM_DONE] Execution finished successfully.");
        $finish;
    end

endmodule
