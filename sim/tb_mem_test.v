`timescale 1ns / 1ps

module tb_mem_test;
    reg clk;
    reg rst_n;
    reg host_we;
    reg [7:0] host_addr;
    reg [23:0] host_wdata;
    wire [23:0] host_rdata;

    polyflex_top dut (
        .clk(clk), .rst_n(rst_n),
        .mode_kyber(1'b0), .is_gs(1'b0), .start(1'b0),
        .busy(), .done(),
        .host_we(host_we), .host_addr(host_addr),
        .host_wdata(host_wdata), .host_rdata(host_rdata)
    );
    always #5 clk = ~clk;
    integer i, err;
    initial begin
        clk = 0; rst_n = 0; host_we = 0; host_addr = 0; host_wdata = 0; err = 0;
        #20; rst_n = 1; #20;
        for (i=0; i<256; i=i+1) begin
            @(negedge clk);
            host_we = 1; host_addr = i[7:0]; host_wdata = i + 100;
        end
        @(negedge clk); host_we = 0;
        for (i=0; i<256; i=i+1) begin
            @(negedge clk);
            host_addr = i[7:0];
            @(negedge clk);
            if (host_rdata !== (i + 100)) begin
                $display("Mismatch at %d: got %d, expected %d", i, host_rdata, i+100);
                err = err + 1;
            end
        end
        if (err == 0) $display("ALL MEMORY READBACK PASSED!");
        else $display("Total mem errors: %d", err);
        $finish;
    end
endmodule
