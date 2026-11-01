`timescale 1ns / 1ps

// ============================================================================
// Module: polyflex_axi_wrapper
// Description: Production-Ready AXI4-Lite SoC Integration Wrapper for PolyFlex-NTT
//              Provides standard memory-mapped CSRs (Control, Status, Performance)
//              and direct coefficient MMIO window (0x100 - 0x4FC) with IRQ support.
// Standard: AMBA 4 AXI4-Lite Protocol Specification
// ============================================================================

module polyflex_axi_wrapper #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 12
)(
    // Global Clock and Reset
    input  wire                                s_axi_aclk,
    input  wire                                s_axi_aresetn,

    // AXI4-Lite Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       s_axi_awaddr,
    input  wire                                s_axi_awvalid,
    output reg                                 s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]       s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]   s_axi_wstrb,
    input  wire                                s_axi_wvalid,
    output reg                                 s_axi_wready,

    // AXI4-Lite Write Response Channel
    output reg  [1:0]                          s_axi_bresp,
    output reg                                 s_axi_bvalid,
    input  wire                                s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       s_axi_araddr,
    input  wire                                s_axi_arvalid,
    output reg                                 s_axi_arready,

    // AXI4-Lite Read Data Channel
    output reg  [C_S_AXI_DATA_WIDTH-1:0]       s_axi_rdata,
    output reg  [1:0]                          s_axi_rresp,
    output reg                                 s_axi_rvalid,
    input  wire                                s_axi_rready,

    // Hardware Interrupt Output
    output reg                                 irq
);

    // ========================================================================
    // Register Map & Memory Addressing
    // ========================================================================
    // 0x000: REG_CONTROL    [0]: START (auto-clears)
    //                       [1]: SOFT_RESET
    //                       [2]: MODE_KYBER (0: Dilithium, 1: Kyber)
    //                       [3]: IS_GS (0: Forward CT NTT, 1: Inverse GS INTT)
    // 0x004: REG_STATUS     [0]: BUSY
    //                       [1]: DONE (Write 1 to clear)
    //                       [2]: IRQ_ENABLE
    // 0x008: REG_PERF_CYCLE Cycle counter for execution latency benchmark
    // 0x00C: REG_IP_VERSION Core ID = 0x50514331 ("PQC1")
    // 0x100 - 0x4FC: COEFF_WINDOW (256 words x 32 bits, 24-bit payload)
    // ========================================================================

    localparam ADDR_CONTROL    = 12'h000;
    localparam ADDR_STATUS     = 12'h004;
    localparam ADDR_PERF_CYCLE = 12'h008;
    localparam ADDR_VERSION    = 12'h00C;
    localparam ADDR_COEFF_BASE = 12'h100;
    localparam ADDR_COEFF_HIGH = 12'h4FC;

    localparam IP_VERSION_CONST = 32'h50514331; // ASCII "PQC1"

    // Internal Registers
    reg        ctrl_start;
    reg        ctrl_mode_kyber;
    reg        ctrl_is_gs;
    reg        status_done;
    reg        status_irq_en;
    reg [31:0] perf_cycle_cnt;
    reg        perf_counting;

    // Accelerated Core Signals
    wire        core_busy;
    wire        core_done;
    reg         core_host_we;
    reg  [7:0]  core_host_addr;
    reg  [23:0] core_host_wdata;
    wire [23:0] core_host_rdata;

    // Instantiate PolyFlex-NTT Core
    polyflex_top u_core (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .mode_kyber(ctrl_mode_kyber),
        .is_gs(ctrl_is_gs),
        .start(ctrl_start),
        .busy(core_busy),
        .done(core_done),
        .host_we(core_host_we),
        .host_addr(core_host_addr),
        .host_wdata(core_host_wdata),
        .host_rdata(core_host_rdata)
    );

    // ========================================================================
    // Performance Cycle Counter
    // ========================================================================
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            perf_cycle_cnt <= 32'd0;
            perf_counting  <= 1'b0;
        end else begin
            if (ctrl_start) begin
                perf_cycle_cnt <= 32'd0;
                perf_counting  <= 1'b1;
            end else if (perf_counting) begin
                if (core_done) begin
                    perf_counting <= 1'b0;
                end else begin
                    perf_cycle_cnt <= perf_cycle_cnt + 32'd1;
                end
            end
        end
    end

    // ========================================================================
    // AXI4-Lite Write Channel FSM
    // ========================================================================
    reg [1:0] wstate;
    localparam W_IDLE = 2'd0;
    localparam W_DATA = 2'd1;
    localparam W_RESP = 2'd2;

    reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_latched;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            wstate          <= W_IDLE;
            awaddr_latched  <= 12'd0;
            ctrl_start      <= 1'b0;
            ctrl_mode_kyber <= 1'b0;
            ctrl_is_gs      <= 1'b0;
            status_done     <= 1'b0;
            status_irq_en   <= 1'b0;
            core_host_we    <= 1'b0;
            core_host_addr  <= 8'd0;
            core_host_wdata <= 24'd0;
            irq             <= 1'b0;
        end else begin
            // Pulse signals default
            ctrl_start   <= 1'b0;
            core_host_we <= 1'b0;

            // Latch Core Done
            if (core_done) begin
                status_done <= 1'b1;
                if (status_irq_en) irq <= 1'b1;
            end

            case (wstate)
                W_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready  <= 1'b1;
                        s_axi_wready   <= 1'b1;
                        awaddr_latched <= s_axi_awaddr;
                        wstate         <= W_RESP;
                        
                        // Execute direct write
                        if (s_axi_awaddr >= ADDR_COEFF_BASE && s_axi_awaddr <= ADDR_COEFF_HIGH) begin
                            core_host_we    <= 1'b1;
                            core_host_addr  <= (s_axi_awaddr - ADDR_COEFF_BASE) >> 2;
                            core_host_wdata <= s_axi_wdata[23:0];
                        end else begin
                            case (s_axi_awaddr)
                                ADDR_CONTROL: begin
                                    ctrl_start      <= s_axi_wdata[0];
                                    ctrl_mode_kyber <= s_axi_wdata[2];
                                    ctrl_is_gs      <= s_axi_wdata[3];
                                end
                                ADDR_STATUS: begin
                                    if (s_axi_wdata[1]) begin
                                        status_done <= 1'b0;
                                        irq         <= 1'b0;
                                    end
                                    status_irq_en <= s_axi_wdata[2];
                                end
                            endcase
                        end
                    end else if (s_axi_awvalid) begin
                        s_axi_awready  <= 1'b1;
                        awaddr_latched <= s_axi_awaddr;
                        wstate         <= W_DATA;
                    end
                end

                W_DATA: begin
                    s_axi_awready <= 1'b0;
                    if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b1;
                        wstate       <= W_RESP;

                        if (awaddr_latched >= ADDR_COEFF_BASE && awaddr_latched <= ADDR_COEFF_HIGH) begin
                            core_host_we    <= 1'b1;
                            core_host_addr  <= (awaddr_latched - ADDR_COEFF_BASE) >> 2;
                            core_host_wdata <= s_axi_wdata[23:0];
                        end else begin
                            case (awaddr_latched)
                                ADDR_CONTROL: begin
                                    ctrl_start      <= s_axi_wdata[0];
                                    ctrl_mode_kyber <= s_axi_wdata[2];
                                    ctrl_is_gs      <= s_axi_wdata[3];
                                end
                                ADDR_STATUS: begin
                                    if (s_axi_wdata[1]) begin
                                        status_done <= 1'b0;
                                        irq         <= 1'b0;
                                    end
                                    status_irq_en <= s_axi_wdata[2];
                                end
                            endcase
                        end
                    end
                end

                W_RESP: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wstate       <= W_IDLE;
                    end else begin
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= 2'b00; // OKAY
                    end
                end
            endcase
        end
    end

    // ========================================================================
    // AXI4-Lite Read Channel FSM
    // ========================================================================
    reg [1:0] rstate;
    localparam R_IDLE = 2'd0;
    localparam R_WAIT = 2'd1;
    localparam R_DATA = 2'd2;

    reg [C_S_AXI_ADDR_WIDTH-1:0] araddr_latched;

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rdata    <= 32'd0;
            s_axi_rresp    <= 2'b00;
            rstate         <= R_IDLE;
            araddr_latched <= 12'd0;
        end else begin
            case (rstate)
                R_IDLE: begin
                    if (s_axi_arvalid) begin
                        s_axi_arready  <= 1'b1;
                        araddr_latched <= s_axi_araddr;
                        if (s_axi_araddr >= ADDR_COEFF_BASE && s_axi_araddr <= ADDR_COEFF_HIGH) begin
                            // Present read address to internal core SRAM
                            core_host_addr <= (s_axi_araddr - ADDR_COEFF_BASE) >> 2;
                            rstate         <= R_WAIT; // Wait 1 cycle for SRAM read latency
                        end else begin
                            rstate <= R_DATA;
                            case (s_axi_araddr)
                                ADDR_CONTROL:    s_axi_rdata <= {28'd0, ctrl_is_gs, ctrl_mode_kyber, 1'b0, ctrl_start};
                                ADDR_STATUS:     s_axi_rdata <= {29'd0, status_irq_en, status_done, core_busy};
                                ADDR_PERF_CYCLE: s_axi_rdata <= perf_cycle_cnt;
                                ADDR_VERSION:    s_axi_rdata <= IP_VERSION_CONST;
                                default:         s_axi_rdata <= 32'd0;
                            endcase
                        end
                    end
                end

                R_WAIT: begin
                    s_axi_arready <= 1'b0;
                    rstate        <= R_DATA;
                    // Latch data from Core SRAM
                    s_axi_rdata   <= {8'd0, core_host_rdata};
                end

                R_DATA: begin
                    s_axi_arready <= 1'b0;
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rstate       <= R_IDLE;
                    end else begin
                        s_axi_rvalid <= 1'b1;
                        s_axi_rresp  <= 2'b00; // OKAY
                    end
                end
            endcase
        end
    end

endmodule
