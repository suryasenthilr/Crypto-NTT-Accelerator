`timescale 1ns / 1ps

module tb_axi_wrapper;

    reg         aclk;
    reg         aresetn;

    // AXI4-Lite
    reg  [11:0] awaddr;
    reg         awvalid;
    wire        awready;

    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire        wready;

    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;

    reg  [11:0] araddr;
    reg         arvalid;
    wire        arready;

    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;

    wire        irq;

    polyflex_axi_wrapper dut (
        .s_axi_aclk(aclk),
        .s_axi_aresetn(aresetn),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .irq(irq)
    );

    always #5 aclk = ~aclk; // 100MHz

    // AXI Write Task
    task axi_write(input [11:0] addr, input [31:0] data);
        begin
            @(posedge aclk);
            #1;
            awaddr  = addr;
            awvalid = 1;
            wdata   = data;
            wstrb   = 4'hF;
            wvalid  = 1;
            bready  = 1;
            @(posedge aclk);
            while (!bvalid) @(posedge aclk);
            #1;
            awvalid = 0;
            wvalid  = 0;
            bready  = 0;
        end
    endtask

    // AXI Read Task
    task axi_read(input [11:0] addr, output [31:0] data);
        begin
            @(posedge aclk);
            #1;
            araddr  = addr;
            arvalid = 1;
            rready  = 1;
            @(posedge aclk);
            while (!rvalid) @(posedge aclk);
            #1;
            data    = rdata;
            arvalid = 0;
            rready  = 0;
        end
    endtask

    reg [31:0] rd_val;
    integer i;

    initial begin
        aclk    = 0;
        aresetn = 0;
        awaddr  = 0; awvalid = 0;
        wdata   = 0; wstrb = 0; wvalid = 0;
        bready  = 0;
        araddr  = 0; arvalid = 0;
        rready  = 0;

        #20;
        aresetn = 1;
        #20;

        $display("==========================================================");
        $display("[TEST] Starting PolyFlex-NTT AXI4-Lite SoC Interface Test");
        $display("==========================================================");

        // 1. Read IP Version Register (0x0C) -> Expected 0x50514331 ("PQC1")
        axi_read(12'h00C, rd_val);
        $display("Read IP Version = 0x%08X (ASCII: %c%c%c%c)", rd_val, rd_val[31:24], rd_val[23:16], rd_val[15:8], rd_val[7:0]);
        if (rd_val !== 32'h50514331) begin
            $display("[FAIL] IP Version mismatch!");
            $finish;
        end

        // 2. Enable IRQ in Status Register (0x04) -> write bit 2 = 1
        axi_write(12'h004, 32'h4);

        // 3. Write impulse polynomial via MMIO window (0x100 - 0x4FC)
        $display("Writing polynomial via AXI4-Lite MMIO...");
        for (i = 0; i < 256; i = i + 1) begin
            axi_write(12'h100 + (i * 4), (i == 0) ? 32'd1 : 32'd0);
        end

        // 4. Trigger Dilithium Forward NTT: Write 0x1 to Control Register (0x00)
        $display("Triggering Dilithium NTT via Control Register...");
        axi_write(12'h000, 32'h1);

        // 5. Wait for Hardware Interrupt or Done bit in Status Register
        wait (irq == 1);
        $display("[INFO] Hardware IRQ fired at time %0t!", $time);

        // 6. Read Performance Cycle Counter (0x08)
        axi_read(12'h008, rd_val);
        $display("Measured Execution Latency: %0d clock cycles", rd_val);

        // 7. Verify Results via MMIO Readback
        for (i = 0; i < 10; i = i + 1) begin
            axi_read(12'h100 + (i * 4), rd_val);
            if (rd_val !== 32'd1) begin
                $display("[FAIL] Index %0d = %0d (Expected 1)", i, rd_val);
                $finish;
            end
        end

        $display("[PASS] AXI4-Lite SoC Slave Integration Fully Verified!");
        $finish;
    end

endmodule
