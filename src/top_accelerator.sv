`timescale 1ns/1ps

module top_accelerator #(
    parameter LANES     = 4,
    parameter IN_WIDTH  = 8,
    parameter ACC_WIDTH = 32,
    parameter DEPTH     = 16
)(
    input  logic              clk,
    input  logic              rst_n,

    // --- Host Control Interfaces ---
    input  logic              acc_clr,     // Synchronously clears running totals across all lanes
    input  logic              pipeline_en, // Global execution stall control (1=Run, 0=Stall)

    // --- Upstream Streaming Interface (Valid/Ready Handshake) ---
    input  logic              v_in,        // Upstream data payload is valid
    output logic              r_ready,     // Accelerator is ready to accept data
    input  logic signed [(LANES*IN_WIDTH)-1:0] vec_din_a, // Packed 32-bit Vector A input (4x INT8)
    input  logic signed [(LANES*IN_WIDTH)-1:0] vec_din_b, // Packed 32-bit Vector B input (4x INT8)

    // --- Downstream Output Interface (Valid Flag) ---
    output logic              v_out,       // Downstream calculation output is valid
    output logic signed [(LANES*ACC_WIDTH)-1:0] vec_acc_out // Packed 128-bit Vector Output (4x INT32)
);

    // Internal Control Matrix Wires
    logic [LANES-1:0] lane_fifo_empty;
    logic [LANES-1:0] lane_fifo_full;
    logic             all_fifos_have_data;
    logic             mac_exec_en;
    
    // Unpacked internal vectors for routing to/from lanes
    logic signed [IN_WIDTH-1:0]   fifo_a_out [LANES-1:0];
    logic signed [IN_WIDTH-1:0]   fifo_b_out [LANES-1:0];
    logic signed [ACC_WIDTH-1:0]  lane_out   [LANES-1:0];

    // --- Dynamic Flow Control & Backpressure Logic ---
    // The accelerator accepts incoming writes ONLY if none of the internal lane FIFOs are full
    assign r_ready = !( |lane_fifo_full );

    // Core execution steps forward ONLY if there is valid data in all queues and the host hasn't stalled the pipeline
    assign all_fifos_have_data = !( |lane_fifo_empty );
    assign mac_exec_en         = all_fifos_have_data && pipeline_en;

    // --- Structural SIMD Lane Generation Block ---
    genvar i;
    generate
        for (i = 0; i < LANES; i++) begin : simd_lanes
            
            // Dedicated INT8 Input Queue for Operand A Component
            sync_fifo #(.WIDTH(IN_WIDTH), .DEPTH(DEPTH)) fifo_a_inst (
                .clk(clk), .rst_n(rst_n),
                .wr_en(v_in && r_ready), 
                .din(vec_din_a[(i+1)*IN_WIDTH-1 : i*IN_WIDTH]),
                .full(lane_fifo_full[i]),
                .rd_en(mac_exec_en), 
                .dout(fifo_a_out[i]), 
                .empty(lane_fifo_empty[i])
            );

            // Dedicated INT8 Input Queue for Operand B Component
            sync_fifo #(.WIDTH(IN_WIDTH), .DEPTH(DEPTH)) fifo_b_inst (
                .clk(clk), .rst_n(rst_n),
                .wr_en(v_in && r_ready), 
                .din(vec_din_b[(i+1)*IN_WIDTH-1 : i*IN_WIDTH]),
                .full(), // Throttling is globally governed by the unified lane array flags
                .rd_en(mac_exec_en), 
                .dout(fifo_b_out[i]), 
                .empty()
            );

            // Hybrid INT8/INT32 Computing Core
            mac_unit #(
                .IN_WIDTH(IN_WIDTH), 
                .ACC_WIDTH(ACC_WIDTH)
            ) mac_core (
                .clk(clk), .rst_n(rst_n),
                .en(mac_exec_en), .clr(acc_clr),
                .a_in(fifo_a_out[i]), .b_in(fifo_b_out[i]),
                .out(lane_out[i])
            );

            // Pack parallel internal array channels back out onto the wide vector bus
            assign vec_acc_out[(i+1)*ACC_WIDTH-1 : i*ACC_WIDTH] = lane_out[i];
        end
    endgenerate

    // --- Control-Path Valid Delay Pipeline ---
    logic [1:0] valid_pipe;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 2'b00;
        end else if (pipeline_en) begin
            // Shift validity flag down the pipeline only if the engine isn't actively stalled
            valid_pipe <= {valid_pipe[0], mac_exec_en};
        end
    end
    
    // Assign downstream valid flag based on the 2-cycle execution latency
    assign v_out = valid_pipe[1];

endmodule