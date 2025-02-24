`timescale 1ns / 1ps
// =============================================================================
//  Program : data_feeder.v
//  Author  : YUE
//  Date    : Feb/5/2025
// -----------------------------------------------------------------------------
//  Description:
//  This module implements the RISC-V Core DSA data Controller.
//  It will control the data flow of the DSA with MMIO.
// =============================================================================

`include "aquila_config.vh"

module data_feeder
#( parameter XLEN = 32 )
(
    input                   clk_i,
    input                   rst_i,

    input                   en_i,
    input                   we_i,
    (* mark_debug = "true" *) input [XLEN-1 : 0]      addr_i,
    input [XLEN-1 : 0]      data_i,
    output reg [XLEN-1 : 0] data_o,
    (* mark_debug = "true" *) output                 data_ready_o

);

integer idx;


(* mark_debug = "true" *) reg [XLEN-1:0] fcc_data_a, fcc_data_b, fcc_data_c;
reg fcc_data_valid;
(* mark_debug = "true" *) reg fcc_need_bias;
reg [XLEN-1:0] fcc_bias;

(* mark_debug = "true" *) wire fcc_result_valid, fcc_result_with_b_valid;
(* mark_debug = "true" *) reg [XLEN-1:0] fcc_result_data_reg, fcc_result_with_b_data_reg;
(* mark_debug = "true" *) wire [XLEN-1:0] fcc_result_data, fcc_result_with_b_data;

(* mark_debug = "true" *) reg [XLEN-1:0] avg_data;
(* mark_debug = "true" *) reg avg_data_valid;
(* mark_debug = "true" *) wire avg_result_valid;
(* mark_debug = "true" *) reg [XLEN-1:0] avg_result_data_reg;
(* mark_debug = "true" *) wire [XLEN-1:0] avg_result_data;

reg [XLEN-1 : 0] dsa_mem[0:4];


// for fcc and cnn
always @(posedge clk_i) begin
    if(rst_i) begin
        fcc_bias <= 32'b0;
    end
    else if(en_i) begin
        if(we_i && addr_i == 32'hC4200008) begin
            fcc_bias <= data_i;
        end
    end
    else begin
        fcc_bias <= fcc_bias;
    end
end

always @(posedge clk_i) begin
    if (rst_i) begin
        fcc_data_a <= 32'b0;
        fcc_data_b <= 32'b0;
        fcc_data_c <= 32'b0;
        fcc_need_bias <= 1'b0;
    end
    else if(en_i) begin
        if(we_i && addr_i == 32'hC420_0000) begin
            fcc_data_a <= data_i;
        end
        else if(we_i && addr_i == 32'hC422_0000) begin
            fcc_data_b <= data_i;
            fcc_data_c <= fcc_result_data_reg;
            fcc_data_valid <= 1'b1;
        end
        else if(we_i && addr_i == 32'hC420_0004) begin
            fcc_need_bias <= data_i[0];
        end
    end
    else if(fcc_result_valid) begin
        fcc_data_valid <= 1'b0;
    end
    else begin
        fcc_data_a <= fcc_data_a;
        fcc_data_b <= fcc_data_b;
        fcc_data_c <= fcc_data_c;
        fcc_data_valid <= fcc_data_valid;
        fcc_need_bias <= fcc_need_bias;
    end
end


// for average pooling
always @(posedge clk_i) begin
    if (rst_i) begin

    end
    else if(en_i) begin
        if(we_i && addr_i == 32'hC440_0000) begin
            avg_data <= data_i;
            avg_data_valid <= 1'b1;
        end
        else if(we_i && addr_i == 32'hC444_0000) begin
            avg_data <= 32'b0;
            avg_data_valid <= 1'b0;
        end
    end
    else if(avg_result_valid) begin
        avg_data_valid <= 1'b0;
    end
    else begin
        avg_data_valid <= avg_data_valid;
        avg_data <= avg_data;
    end
end




(* mark_debug = "true" *) reg [3-1:0] S;
localparam STATE_IDLE = 3'b000, STATE_SET = 3'b001, STATE_COMPUTE = 3'b010, STATE_GET = 3'b100;
assign data_ready_o = ~(S == STATE_COMPUTE);


always @(posedge clk_i) begin
    if(rst_i) begin
        S <= STATE_IDLE;
    end
    else if(S == STATE_IDLE) begin
        if(en_i && we_i) begin
            if(addr_i == 32'hC420_0000) begin
                S <= STATE_SET;
            end
            else if(addr_i == 32'hC440_0000) begin
                S <= STATE_COMPUTE;
            end
        end
    end
    else if(S == STATE_SET) begin
        if(fcc_data_valid) begin
            S <= STATE_COMPUTE;
        end
    end
    else if(S == STATE_COMPUTE) begin
        if(fcc_result_valid || avg_result_valid) begin
            S <= STATE_IDLE;
        end
    end
    else begin
        S <= S;
    end
end

always @(posedge clk_i) begin
    if(rst_i) begin
        fcc_result_with_b_data_reg <= 32'b0;
    end
    else if(fcc_result_with_b_valid) begin
        fcc_result_with_b_data_reg <= fcc_result_with_b_data;
    end
    else begin
        fcc_result_with_b_data_reg <= fcc_result_with_b_data_reg;
    end
end



always @(posedge clk_i) begin
    if(rst_i) begin
        fcc_result_data_reg <= 32'b0;
        avg_result_data_reg <= 32'b0;
        data_o <= 32'b0;
    end
    else if(S == STATE_COMPUTE) begin
        data_o <= 32'b0;
        if(fcc_result_valid) begin
            fcc_result_data_reg <= fcc_result_data;
        end
        
        if(avg_result_valid) begin
            avg_result_data_reg <= avg_result_data;
        end
    end
    else if(addr_i == 32'hC424_0000) begin
        fcc_result_data_reg <= 32'b0;
        if(fcc_need_bias) begin
            data_o <= fcc_result_with_b_data_reg;
        end
        else begin
            data_o <= fcc_result_data_reg;
        end
    end
    else if(addr_i == 32'hC444_0000) begin
        data_o <= avg_result_data_reg;
        avg_result_data_reg <= 32'b0;
    end
    else begin
        fcc_result_data_reg <= fcc_result_data_reg;
        data_o <= data_o;
    end
end



floating_point_fuse fcc_mul(
    .aclk(clk_i),

    .s_axis_a_tvalid(fcc_data_valid),
    .s_axis_a_tdata(fcc_data_a),

    .s_axis_b_tvalid(fcc_data_valid),
    .s_axis_b_tdata(fcc_data_b),

    .s_axis_c_tvalid(fcc_data_valid),
    .s_axis_c_tdata(fcc_data_c),

    .m_axis_result_tvalid(fcc_result_valid),
    .m_axis_result_tdata(fcc_result_data)
);

floating_point_add fcc_add(
    .aclk(clk_i),

    .s_axis_a_tvalid(fcc_result_valid),
    .s_axis_a_tdata(fcc_result_data_reg),

    .s_axis_b_tvalid(fcc_result_valid),
    .s_axis_b_tdata(fcc_bias),

    .m_axis_result_tvalid(fcc_result_with_b_valid),
    .m_axis_result_tdata(fcc_result_with_b_data)
);

floating_point_add avg_add(
    .aclk(clk_i),

    .s_axis_a_tvalid(avg_data_valid),
    .s_axis_a_tdata(avg_result_data_reg),

    .s_axis_b_tvalid(avg_data_valid),
    .s_axis_b_tdata(avg_data),

    .m_axis_result_tvalid(avg_result_valid),
    .m_axis_result_tdata(avg_result_data)
);


endmodule
