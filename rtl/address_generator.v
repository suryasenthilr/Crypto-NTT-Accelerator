`timescale 1ns / 1ps

// ============================================================================
// Module: address_generator
// Description: Conflict-Free Dual-Bank Address & Twiddle Index Generator
//              Implements hardware bit-insertion and parity-based bank mapping.
//              Guarantees ZERO bank collisions for all stages of CT and GS.
// ============================================================================

module address_generator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        mode_kyber,  // 1: Kyber (7 stages), 0: Dilithium (8 stages)
    input  wire        is_gs,       // 0: CT (Forward NTT), 1: GS (Inverse INTT)
    output reg         busy,
    output reg         done,
    
    // Read Controls to Dual-Bank SRAM
    output reg         ren0,
    output reg  [6:0]  raddr0,
    output reg         ren1,
    output reg  [6:0]  raddr1,
    output wire        read_u_from_bank1, // 1 if u is in Bank 1, 0 if u is in Bank 0
    
    // Twiddle ROM Address
    output reg  [7:0]  twiddle_addr,
    
    // Write Controls to Dual-Bank SRAM (delayed 4 cycles for pipeline writeback)
    output wire        wen0,
    output wire [6:0]  waddr0,
    output wire        wen1,
    output wire [6:0]  waddr1,
    output wire        write_u_to_bank1
);

    // FSM States
    localparam S_IDLE  = 2'd0;
    localparam S_RUN   = 2'd1;
    localparam S_FLUSH = 2'd2;
    localparam S_DONE  = 2'd3;

    reg [1:0] state;
    reg [2:0] stage_cnt;
    reg [6:0] pair_cnt;
    reg [2:0] flush_cnt;

    wire [2:0] max_stages = mode_kyber ? 3'd6 : 3'd7; // 7 stages (0..6) or 8 stages (0..7)

    // Split position for bit-insertion
    wire [2:0] split_pos = is_gs ? (mode_kyber ? (stage_cnt + 3'd1) : stage_cnt) : (3'd7 - stage_cnt);

    // Dynamic bit insertion
    // u has 0 at split_pos, v has 1 at split_pos
    reg [7:0] u_idx, v_idx;
    always @(*) begin
        case (split_pos)
            3'd0: begin
                u_idx = {pair_cnt[6:0], 1'b0};
                v_idx = {pair_cnt[6:0], 1'b1};
            end
            3'd1: begin
                u_idx = {pair_cnt[6:1], 1'b0, pair_cnt[0]};
                v_idx = {pair_cnt[6:1], 1'b1, pair_cnt[0]};
            end
            3'd2: begin
                u_idx = {pair_cnt[6:2], 1'b0, pair_cnt[1:0]};
                v_idx = {pair_cnt[6:2], 1'b1, pair_cnt[1:0]};
            end
            3'd3: begin
                u_idx = {pair_cnt[6:3], 1'b0, pair_cnt[2:0]};
                v_idx = {pair_cnt[6:3], 1'b1, pair_cnt[2:0]};
            end
            3'd4: begin
                u_idx = {pair_cnt[6:4], 1'b0, pair_cnt[3:0]};
                v_idx = {pair_cnt[6:4], 1'b1, pair_cnt[3:0]};
            end
            3'd5: begin
                u_idx = {pair_cnt[6:5], 1'b0, pair_cnt[4:0]};
                v_idx = {pair_cnt[6:5], 1'b1, pair_cnt[4:0]};
            end
            3'd6: begin
                u_idx = {pair_cnt[6], 1'b0, pair_cnt[5:0]};
                v_idx = {pair_cnt[6], 1'b1, pair_cnt[5:0]};
            end
            3'd7: begin
                u_idx = {1'b0, pair_cnt[6:0]};
                v_idx = {1'b1, pair_cnt[6:0]};
            end
        endcase
    end

    // Twiddle index k
    wire [6:0] g = pair_cnt >> split_pos;
    reg [7:0] k_val;
    always @(*) begin
        if (!is_gs) begin
            // CT: k = (1 << stage_cnt) + g
            k_val = (8'd1 << stage_cnt) + {1'b0, g};
        end else begin
            // GS: k counts downward
            if (mode_kyber) begin
                k_val = (8'd1 << (4'd7 - {1'b0, stage_cnt})) - 8'd1 - {1'b0, g};
            end else begin
                k_val = (8'd1 << (4'd8 - {1'b0, stage_cnt})) - 8'd1 - {1'b0, g};
            end
        end
    end

    // Parity-based bank assignment: XOR all 8 bits
    wire bank_u = ^u_idx;
    wire bank_v = ~bank_u; // Mathematically proven to always be opposite!

    // Internal 7-bit addresses
    wire [6:0] addr_u = u_idx[7:1];
    wire [6:0] addr_v = v_idx[7:1];

    // Read control generation
    wire ren0_w = (state == S_RUN);
    wire ren1_w = (state == S_RUN);
    wire [6:0] raddr0_w = bank_u ? addr_v : addr_u;
    wire [6:0] raddr1_w = bank_u ? addr_u : addr_v;

    // ------------------------------------------------------------------------
    // Writeback Pipeline Delay:
    // t=10: raddr updated, bank_u_p1 updated
    // t=20: SRAM rdata emerges, bank_u_p2 updated -> read_u_from_bank1 = bank_u_p2
    // t=30: Butterfly stage 1 (prod registered, bank_u_p3 updated)
    // t=40: Butterfly stage 2 (out_p registered, bank_u_p4 updated)
    // t=50: Butterfly stage 3 (u_out/v_out emerge, bank_u_p5 updated -> waddr/wen valid)
    // t=60: SRAM writes u_out/v_out into memory
    // ------------------------------------------------------------------------
    reg [4:0] valid_pipe;
    reg [6:0] waddr0_p1, waddr0_p2, waddr0_p3, waddr0_p4, waddr0_p5;
    reg [6:0] waddr1_p1, waddr1_p2, waddr1_p3, waddr1_p4, waddr1_p5;
    reg       bank_u_p1, bank_u_p2, bank_u_p3, bank_u_p4, bank_u_p5;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 5'd0;
            waddr0_p1  <= 7'd0; waddr0_p2 <= 7'd0; waddr0_p3 <= 7'd0; waddr0_p4 <= 7'd0; waddr0_p5 <= 7'd0;
            waddr1_p1  <= 7'd0; waddr1_p2 <= 7'd0; waddr1_p3 <= 7'd0; waddr1_p4 <= 7'd0; waddr1_p5 <= 7'd0;
            bank_u_p1  <= 1'b0; bank_u_p2 <= 1'b0; bank_u_p3 <= 1'b0; bank_u_p4 <= 1'b0; bank_u_p5 <= 1'b0;
        end else begin
            valid_pipe <= {valid_pipe[3:0], (state == S_RUN)};

            waddr0_p1 <= raddr0_w;
            waddr0_p2 <= waddr0_p1;
            waddr0_p3 <= waddr0_p2;
            waddr0_p4 <= waddr0_p3;
            waddr0_p5 <= waddr0_p4;

            waddr1_p1 <= raddr1_w;
            waddr1_p2 <= waddr1_p1;
            waddr1_p3 <= waddr1_p2;
            waddr1_p4 <= waddr1_p3;
            waddr1_p5 <= waddr1_p4;

            bank_u_p1 <= bank_u;
            bank_u_p2 <= bank_u_p1;
            bank_u_p3 <= bank_u_p2;
            bank_u_p4 <= bank_u_p3;
            bank_u_p5 <= bank_u_p4;
        end
    end

    // Pipeline aligned controls
    assign read_u_from_bank1 = bank_u_p2; // Aligned with SRAM rdata at t=20
    assign wen0              = valid_pipe[4]; // Aligned with Butterfly u_out/v_out at t=50
    assign wen1              = valid_pipe[4];
    assign waddr0            = waddr0_p5;
    assign waddr1            = waddr1_p5;
    assign write_u_to_bank1  = bank_u_p5;

    // ------------------------------------------------------------------------
    // FSM Execution
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            stage_cnt         <= 3'd0;
            pair_cnt          <= 7'd0;
            flush_cnt         <= 2'd0;
            busy              <= 1'b0;
            done              <= 1'b0;
            ren0              <= 1'b0;
            ren1              <= 1'b0;
            raddr0            <= 7'd0;
            raddr1            <= 7'd0;
            twiddle_addr      <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state             <= S_RUN;
                        busy              <= 1'b1;
                        stage_cnt         <= 3'd0;
                        pair_cnt          <= 7'd0;
                        flush_cnt         <= 3'd0;
                        ren0              <= 1'b1;
                        ren1              <= 1'b1;
                        raddr0            <= raddr0_w;
                        raddr1            <= raddr1_w;
                        twiddle_addr      <= k_val;
                    end else begin
                        busy <= 1'b0;
                        ren0 <= 1'b0;
                        ren1 <= 1'b0;
                    end
                end

                S_RUN: begin
                    ren0              <= 1'b1;
                    ren1              <= 1'b1;
                    raddr0            <= raddr0_w;
                    raddr1            <= raddr1_w;
                    twiddle_addr      <= k_val;

                    if (pair_cnt == 7'd127) begin
                        pair_cnt <= 7'd0;
                        if (stage_cnt == max_stages) begin
                            state     <= S_FLUSH;
                            flush_cnt <= 3'd0;
                        end else begin
                            stage_cnt <= stage_cnt + 3'd1;
                        end
                    end else begin
                        pair_cnt <= pair_cnt + 7'd1;
                    end
                end

                S_FLUSH: begin
                    ren0 <= 1'b0;
                    ren1 <= 1'b0;
                    if (flush_cnt == 3'd5) begin
                        state <= S_DONE;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                    end else begin
                        flush_cnt <= flush_cnt + 3'd1;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
