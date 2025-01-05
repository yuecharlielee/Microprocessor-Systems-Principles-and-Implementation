`timescale 1ns / 1ps


module profiler #(parameter XLEN = 32)
(
    input                       clk_i,
    input                       rst_i,
    input                       stall_i,


    input  [XLEN-1 : 0]         pc_i,
    input                       w_en_i,
    input                       r_en_i,
    
    output [XLEN*5-1 : 0]       prof_cnt_o,
    output [XLEN-1 : 0]         total_cnt_o,
    output [XLEN-1 : 0]         stall_cnt_o,

    (* mark_debug = "true" *) output reg [XLEN-1 : 0]     test_mem_counter,
    (* mark_debug = "true" *) output reg [XLEN-1 : 0]     test_stall_counter

);


// start and end of counting area 
//2ef0:	998fe0ef          	jal	1088 <main>
//17a4:	00008067          	ret
reg start_area_flag;
reg end_area_flag;

wire total_cycle_flag = start_area_flag && !end_area_flag;

always @(posedge clk_i) begin
    if(rst_i) begin 
        start_area_flag <= 1'b0;
        end_area_flag <= 1'b0;
    end
    else begin
        if(pc_i == 32'h0000_1088)
            start_area_flag <= 1'b1;
        if(pc_i == 32'h0000_17a4)
            end_area_flag <= 1'b1;
    end
end


// Profiling flags
// check each function area in coremark.objdump
wire core_list_find_flag = pc_i >= 32'h0000_1d0c && pc_i <= 32'h0000_1d5c;
wire core_list_reverse_flag = pc_i >= 32'h0000_1d60 && pc_i <= 32'h0000_1d80 ;
wire core_state_transition_flag = pc_i >= 32'h0000_2a40 && pc_i <= 32'h0000_2d30 ;
wire matrix_mul_matrix_bitextract_flag = pc_i >= 32'h0000_26a0 && pc_i <= 32'h0000_2758 ;
wire crcu8_flag = pc_i >= 32'h0000_19c8 && pc_i <= 32'h0000_1a0c;

//Profiling counter
// total cycles of function
(* mark_debug = "true" *) reg [XLEN-1:0] total_cycle_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] core_list_find_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] core_list_reverse_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] core_state_transition_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] matrix_mul_matrix_bitextract_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] crcu8_counter;

//memory instruction cycles of function
(* mark_debug = "true" *) reg [XLEN-1:0] core_list_find_memory_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] core_list_reverse_memory_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] core_state_transition_memory_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] matrix_mul_matrix_bitextract_memory_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] crcu8_memory_counter;

// stall cycles of function
(* mark_debug = "true" *) reg [XLEN-1:0] core_list_find_stall_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] core_list_reverse_stall_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] core_state_transition_stall_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] matrix_mul_matrix_bitextract_stall_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] crcu8_stall_counter;



// Load/Store flags
wire load_flag = r_en_i && total_cycle_flag;
wire store_flag = w_en_i && total_cycle_flag;

// stall flag
wire stall_flag = stall_i && total_cycle_flag;

(* mark_debug = "true" *) reg [XLEN-1:0] load_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] store_counter;
(* mark_debug = "true" *) reg [XLEN-1:0] stall_counter;
always @(posedge clk_i) begin
    if (rst_i) begin
        load_counter <= 32'h0000_0000;
        store_counter <= 32'h0000_0000;
        stall_counter <= 32'h0000_0000;
    end
    else begin
        if (load_flag)
            load_counter <= load_counter + 1;
        if (store_flag)
            store_counter <= store_counter + 1;
        if (stall_flag)
            stall_counter <= stall_counter + 1;
    end
end



always @(posedge clk_i) 
begin
    if (rst_i)
    begin
        core_list_find_counter <= 32'h0000_0000;
        core_list_reverse_counter <= 32'h0000_0000;
        core_state_transition_counter <= 32'h0000_0000;
        matrix_mul_matrix_bitextract_counter <= 32'h0000_0000;
        crcu8_counter <= 32'h0000_0000;
        total_cycle_counter <= 32'h0000_0000;

        core_list_find_stall_counter <= 32'h0000_0000;
        core_list_reverse_stall_counter <= 32'h0000_0000;
        core_state_transition_stall_counter <= 32'h0000_0000;
        matrix_mul_matrix_bitextract_stall_counter <= 32'h0000_0000;
        crcu8_stall_counter <= 32'h0000_0000;

        core_list_find_memory_counter <= 32'h0000_0000;
        core_list_reverse_memory_counter <= 32'h0000_0000;
        core_state_transition_memory_counter <= 32'h0000_0000;
        matrix_mul_matrix_bitextract_memory_counter <= 32'h0000_0000;
        crcu8_memory_counter <= 32'h0000_0000;

        test_mem_counter <= 32'h0000_0000;
        test_stall_counter <= 32'h0000_0000;
    end
    else
    begin
        if (total_cycle_flag) begin
            total_cycle_counter <= total_cycle_counter + 1;
        end

        if (core_list_find_flag) begin
            core_list_find_counter <= core_list_find_counter + 1;
            if(stall_flag) begin
                core_list_find_stall_counter <= core_list_find_stall_counter + 1;
                test_stall_counter <= test_stall_counter + 1;
            end
                
            if(load_flag || store_flag) begin
                core_list_find_memory_counter <= core_list_find_memory_counter + 1;
                test_mem_counter <= test_mem_counter + 1;
            end
        end
        if (core_list_reverse_flag) begin
            core_list_reverse_counter <= core_list_reverse_counter + 1;
            if(stall_flag)
                core_list_reverse_stall_counter <= core_list_reverse_stall_counter + 1;
            if(load_flag || store_flag)
                core_list_reverse_memory_counter <= core_list_reverse_memory_counter + 1;
        end
        if (core_state_transition_flag) begin
            core_state_transition_counter <= core_state_transition_counter + 1;
            if(stall_flag)
                core_state_transition_stall_counter <= core_state_transition_stall_counter + 1;
            if(load_flag || store_flag)
                core_state_transition_memory_counter <= core_state_transition_memory_counter + 1;
        end
        if (matrix_mul_matrix_bitextract_flag) begin
            matrix_mul_matrix_bitextract_counter <= matrix_mul_matrix_bitextract_counter + 1;
            if(stall_flag)
                matrix_mul_matrix_bitextract_stall_counter <= matrix_mul_matrix_bitextract_stall_counter + 1;
            if(load_flag || store_flag)
                matrix_mul_matrix_bitextract_memory_counter <= matrix_mul_matrix_bitextract_memory_counter + 1;    
        end
        if (crcu8_flag) begin
            crcu8_counter <= crcu8_counter + 1;
            if(stall_flag)
                crcu8_stall_counter <= crcu8_stall_counter + 1;
            if(load_flag || store_flag)
                crcu8_memory_counter <= crcu8_memory_counter + 1;
        end
    end
end



endmodule
