`timescale 1ns / 1ps
// =============================================================================
//  Program : rap.v
//  Author  : You-Ting Li
//  Date    : Jan/7/2025
// -----------------------------------------------------------------------------
//  Description:
//  This is the Return Address Predictor (RAP) of the Aquila core (A RISC-V core).
// -----------------------------------------------------------------------------
//  Revision information:
// -----------------------------------------------------------------------------
//  License information:
//
//  This software is released under the BSD-3-Clause Licence,
//  see https://opensource.org/licenses/BSD-3-Clause for details.
//  In the following license statements, "software" refers to the
//  "source code" of the complete hardware/software system.
//
//  Copyright 2019,
//                    Embedded Intelligent Systems Lab (EISL)
//                    Deparment of Computer Science
//                    National Chiao Tung Uniersity
//                    Hsinchu, Taiwan.
//
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its contributors
//     may be used to endorse or promote products derived from this software
//     without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
// =============================================================================
`include "aquila_config.vh"

module rap #( parameter ENTRY_NUM = 512, parameter XLEN = 32, parameter STACK_ENTRY_NUM = 32)
(
    // System signals
    input               clk_i,
    input               rst_i,
    input               stall_i,
    input               stall_data_hazard_i,

    // from Program_Counter
    input  [XLEN-1 : 0] pc_i, // Addr of the next instruction to be fetched.

    // from Decode
    input               is_jal_i,
    input               is_ret_i,
    input  [XLEN-1 : 0] dec_pc_i, // Addr of the instr. just processed by decoder.

    // from Execute
    input               exe_is_return_i,
    input               rap_misprediction_i,


    // to Program_Counter
    output              return_addr_hit_o,
    output [XLEN-1 : 0] return_addr_o
);

localparam NBITS = $clog2(ENTRY_NUM);

localparam stack_NBITS = $clog2(STACK_ENTRY_NUM);

wire [NBITS-1 : 0]             read_addr;
wire [NBITS-1 : 0]             write_addr;
wire [XLEN-1 : 0]              ret_inst_tag;
wire                           re_RAS;
wire                           we_RAS;
wire                           we_BHT;
reg                            BHT_hit_ff, BHT_hit;

reg  [stack_NBITS-1 : 0]       stack_pointer;
reg  [XLEN-1 : 0]              stack[stack_NBITS-1 : 0];


wire [stack_NBITS - 1 : 0]  stack_pointer_plus_one = stack_pointer + 1 == STACK_ENTRY_NUM ? 0 : stack_pointer + 1;
wire [stack_NBITS - 1 : 0]  stack_pointer_minus_one = stack_pointer  == 0 ? STACK_ENTRY_NUM - 1 : stack_pointer - 1;

// "we" is enabled to add a new entry to the BHT table when
// the decoded branch instruction is not in the BHT.
assign we_BHT = ~stall_i & (is_ret_i) & !BHT_hit;


// "re_RAS" is enabled to read the return address in the stack when
// the addr of the next instruction is in the BHT.
assign re_RAS = ~stall_i & return_addr_hit_o;

// "we_RAS" is enabled to store the return address in the stack when
// the decoded instruction is a jal instruction.
assign we_RAS = ~stall_i & (is_jal_i);


assign read_addr = pc_i[NBITS+1 : 2];
assign write_addr = dec_pc_i[NBITS+1 : 2];

integer idx;

always @(posedge clk_i)
begin
    if (rst_i)
    begin
        for (idx = 0; idx < STACK_ENTRY_NUM; idx = idx + 1)
            stack[idx] <= 0;
    end
    else if (stall_i | stall_data_hazard_i)
    begin
        for (idx = 0; idx < STACK_ENTRY_NUM; idx = idx + 1)
            stack[idx] <= stack[idx];
    end
    else
    begin
        if (we_RAS) // Execute the jal instruction for the first time.
        begin
            // store the pc + 4 in stack when decode a jal insturction
            stack_pointer <= stack_pointer_plus_one;
            stack[stack_pointer] <= dec_pc_i + 4;
        end
        else if(re_RAS)
        begin
            stack_pointer <= stack_pointer_minus_one;
        end
    end
end

// ===========================================================================
//  Branch History Table (BHT). Here, we use a direct-mapping cache table to
//  store branch history. Each entry of the table contains one fields:
//  the PC of the return instruction (as the tag).
//
distri_ram #(.ENTRY_NUM(ENTRY_NUM), .XLEN(XLEN))
RAP_BHT(
    .clk_i(clk_i),
    .we_i(we_BHT),                  // Write-enabled when the instruction at the Decode
                                //   is a branch and has never been executed before.
    .write_addr_i(write_addr),  // Direct-mapping index for the branch at Decode.
    .read_addr_i(read_addr),    // Direct-mapping Index for the next PC to be fetched.

    .data_i({dec_pc_i}), // Input is not used when 'we' is 0.
    .data_o({ret_inst_tag})
);

// Delay the BHT hit flag at the Fetch stage for two clock cycles (plus stalls)
// such that it can be reused at the Execute stage for BHT update operation.
always @ (posedge clk_i)
begin
    if (rst_i) begin
        BHT_hit_ff <= 1'b0;
        BHT_hit <= 1'b0;
    end
    else if (!stall_i) begin
        BHT_hit_ff <= return_addr_hit_o;
        BHT_hit <= BHT_hit_ff;
    end
end

// ===========================================================================
//  Outputs signals
//
assign return_addr_hit_o = (ret_inst_tag === pc_i) & (pc_i != 0);
assign return_addr_o = stack[stack_pointer_minus_one];

// counter with profiling
(* mark_debug = "true" *) reg [XLEN-1 : 0] hit_counter;
(* mark_debug = "true" *) reg [XLEN-1 : 0] mispredict_counter;

always @(posedge clk_i) begin
    if(rst_i) begin
        hit_counter <= 0;
        mispredict_counter <= 0;
    end
    else begin
        if (return_addr_hit_o)
            hit_counter <= hit_counter + 1;
        if (rap_misprediction_i)
            mispredict_counter <= mispredict_counter + 1;
    end
end


endmodule
