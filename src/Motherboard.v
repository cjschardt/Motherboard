`timescale 1ns / 1ps
`default_nettype none

`define PWM_PERIOD                  8'hff

`define ROTARY_ENCODER_ADDRESS      16'h1000
`define ENCODER_BUTTON_ADDRESS      16'h1004
`define ENCODER_SWITCH_ADDRESS      16'h1008

`define CURRENT_RED_ADDRESS         16'h100c
`define CURRENT_GREEN_ADDRESS       16'h1010
`define CURRENT_BLUE_ADDRESS        16'h1014

`define SAVED_RED_ADDRESS           16'h1018
`define SAVED_GREEN_ADDRESS         16'h101c
`define SAVED_BLUE_ADDRESS          16'h1020 

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 11/25/2017 05:38:31 PM
// Design Name:
// Module Name: Motherboard
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module CLOCK_GENERATOR #(parameter DIVIDE = 2)
(
    input wire rst,
    input wire fast_clk,
    output reg slow_clk
);

reg [31:0] counter = 0;

always @(posedge fast_clk or posedge rst)
begin
    if(rst)
    begin
        slow_clk <= 0;
        counter <= 0;
    end
    else
    begin
        if(counter == DIVIDE/2)
        begin
            slow_clk <= ~slow_clk;
            counter <= 0;
        end
        else
        begin
            slow_clk <= slow_clk;
            counter <= counter + 1;
        end
    end
end

endmodule

module ONESHOT(
    input wire clk,
    input wire rst,
    input wire signal,
    output reg out
);

reg previously_high;

always @(posedge clk or posedge rst)
begin
    if(rst)
    begin
        out <= 0;
        previously_high <= 0;
    end
    else
    begin
        if(signal && !previously_high)
        begin
            out <= 1;
            previously_high <= 1;
        end
        else if(signal && previously_high)
        begin
            out <= 0;
            previously_high <= 1;
        end
        else
        begin
            out <= 0;
            previously_high <= 0;
        end
    end
end

endmodule

module Motherboard #(parameter CLOCK_DIVIDER = 100)
(
	//// input 100 MHz clock
    input wire clk100Mhz,
    input wire clk_select,
    input wire button_clock,
    input wire rst,
    input wire ext_phase_a, ext_phase_b,
    input wire ext_button, ext_switch,
    output wire [2:0] LED_L, LED_R
);

// ==================================
//// Internal Parameter Field
// ==================================
parameter ROM_SIZE      = 32'h400/4;
`define ROM_PC_RANGE    ($clog2(ROM_SIZE)+2):2
// ==================================
//// Wires
// ==================================
//// Clock Signals
wire clk;
wire button_clock_sync;
wire cpu_clk;
//// CPU Signals
wire [31:0] AddressBus, DataBus;
wire [31:0] ProgramCounter, ALUResult, RegOut1, RegOut2, RegWriteData, RegWriteAddress;
wire [31:0] Instruction;
wire [3:0] MemWrite;
wire MemWrite_en;
wire MemRead, BusCycle;
//// Address Decoding Signals
wire text_access;
wire extern_access;
wire ram_access;
wire quad_we = 0;
wire quad_dir;
wire quad_decode_cs;
wire btn_cs;
wire cur_r_reg_cs, cur_g_reg_cs, cur_b_reg_cs, sav_r_reg_cs, sav_g_reg_cs, sav_b_reg_cs;
wire [7:0] cur_r_reg_q, cur_g_reg_q, cur_b_reg_q, sav_r_reg_q, sav_g_reg_q, sav_b_reg_q;
wire [7:0] cur_r_prev_q, cur_g_prev_q, cur_b_prev_q;
wire [7:0] r_mux_out, g_mux_out, b_mux_out, prev_r_mux_out, prev_g_mux_out, prev_b_mux_out;
wire [2:0] cur_r_comp_out, cur_g_comp_out, cur_b_comp_out, r_mux_comp_out, g_mux_comp_out, b_mux_comp_out;
wire pwm_l_r_cs, pwm_l_g_cs, pwm_l_b_cs, pwm_r_r_cs, pwm_r_g_cs, pwm_r_b_cs;
// ==================================
//// Wire Assignments
// ==================================
assign pwm_l_r_cs = !cur_r_comp_out[1];
assign pwm_l_g_cs = !cur_g_comp_out[1];
assign pwm_l_b_cs = !cur_b_comp_out[1];
assign pwm_r_r_cs = !r_mux_comp_out[1];
assign pwm_r_g_cs = !g_mux_comp_out[1];
assign pwm_r_b_cs = !b_mux_comp_out[1];
// ==================================
//// Modules
// ==================================
CLOCK_GENERATOR #(.DIVIDE(CLOCK_DIVIDER)
) clock (
    .rst(rst),
    .fast_clk(clk100Mhz),
    .slow_clk(cpu_clk)
);

 Syncronizer #(
 	.WIDTH(1),
 	.DEFAULT_DISABLED(0)
 ) button_clk (
 	.clk(clk100Mhz),
 	.rst(rst),
 	.en(1'b1),
 	.in(button_clock),
 	.sync_out(button_clock_sync)
);


MUX #(
    .WIDTH(1),
    .INPUTS(2)
) register_destination_mux (
    .select(clk_select),
    .in({ cpu_clk, button_clock_sync }),
    .out(clk)
);

ROM #(
    .LENGTH(ROM_SIZE),
    .WIDTH(32),
    .FILE_NAME("rom.mem")
) rom (
	.a(ProgramCounter[`ROM_PC_RANGE]),
	.out(Instruction)
);

MIPS mips(
    .clk(!cpu_clk),
    .rst(rst),
    .BusCycle(BusCycle),
    .MemWrite(MemWrite),
    .MemRead(MemRead),
    .AddressBus(AddressBus),
    .DataBus(DataBus),
    .ProgramCounter(ProgramCounter),
    .ALUResult(ALUResult),
    .RegOut1(RegOut1),
    .RegOut2(RegOut2),
    .RegWriteData(RegWriteData),
    .RegWriteAddress(RegWriteAddress),
    .Instruction(Instruction)
);

RAM #(
    .LENGTH(32'h1000/4),
    .USE_FILE(1),
    .WIDTH(32),
    .MINIMUM_SECTIONAL_WIDTH(8),
    .FILE_NAME("ram.mem")
) ram (
    .clk(cpu_clk),
    .we(MemWrite),
    .cs(ram_access),
    .oe(MemRead),
    .address(AddressBus[13:2]),
    .data(DataBus)
);


CUSTOMDECODER address_decoder
(
	.enable(1'b1),
	.in(AddressBus[14:12]),
	.out({ ram_access, extern_access, text_access })
);

AND #(.WIDTH(4)) MemWrite_en_and (
    .in(MemWrite),
    .out(MemWrite_en)
);

AND #(.WIDTH(3)) quad_decode_cs_and (
    .in({extern_access, (AddressBus == `ROTARY_ENCODER_ADDRESS), MemRead}),
    .out(quad_decode_cs)
);

AND #(.WIDTH(3)) ext_btn_and (
    .in({extern_access, (AddressBus == `ENCODER_BUTTON_ADDRESS), MemRead}),
    .out(btn_cs)
);

AND #(.WIDTH(3)) cur_r_reg_and (
    .in({extern_access, (AddressBus == `CURRENT_RED_ADDRESS), MemWrite_en}),
    .out(cur_r_reg_cs)
);

AND #(.WIDTH(3)) cur_g_reg_and (
    .in({extern_access, (AddressBus == `CURRENT_GREEN_ADDRESS), MemWrite_en}),
    .out(cur_g_reg_cs)
);

AND #(.WIDTH(3)) cur_b_reg_and (
    .in({extern_access, (AddressBus == `CURRENT_BLUE_ADDRESS), MemWrite_en}),
    .out(cur_b_reg_cs)
);

AND #(.WIDTH(3)) sav_r_reg_and (
    .in({extern_access, (AddressBus == `SAVED_RED_ADDRESS), MemWrite_en}),
    .out(sav_r_reg_cs)
);
   
AND #(.WIDTH(3)) sav_g_reg_and (
    .in({extern_access, (AddressBus == `SAVED_GREEN_ADDRESS), MemWrite_en}),
    .out(sav_g_reg_cs)
);

AND #(.WIDTH(3)) sav_b_reg_and (
    .in({extern_access, (AddressBus == `SAVED_BLUE_ADDRESS), MemWrite_en}),
    .out(sav_b_reg_cs)
);

REGISTER #(.WIDTH(8)
) current_red_reg (
    .rst(rst),
    .clk(cpu_clk),
    .load(cur_r_reg_cs),
    .D(DataBus[7:0]),
    .Q(cur_r_reg_q)
);

REGISTER #(.WIDTH(8)
) current_red_prev (
    .rst(rst),
    .clk(cpu_clk),
    .load(!cur_r_comp_out[1]),
    .D(cur_r_reg_q),
    .Q(cur_r_prev_q)
);

Comparator #(.WIDTH(8)
) current_red_comparator (
    .in({cur_r_reg_q, cur_r_prev_q}),
    .out(cur_r_comp_out)
);

REGISTER #(.WIDTH(8)
) current_green_reg (
    .rst(rst),
    .clk(cpu_clk),
    .load(cur_g_reg_cs),
    .D(DataBus[7:0]),
    .Q(cur_g_reg_q)
);

REGISTER #(.WIDTH(8)
) current_green_prev (
    .rst(rst),
    .clk(cpu_clk),
    .load(!cur_g_comp_out[1]),
    .D(cur_g_reg_q),
    .Q(cur_g_prev_q)
);

Comparator #(.WIDTH(8)
) current_green_comparator (
    .in({cur_g_reg_q, cur_g_prev_q}),
    .out(cur_g_comp_out)
);

REGISTER #(.WIDTH(8)
) current_blue_reg (
    .rst(rst),
    .clk(cpu_clk),
    .load(cur_b_reg_cs),
    .D(DataBus[7:0]),
    .Q(cur_b_reg_q)
);

REGISTER #(.WIDTH(8)
) current_blue_prev (
    .rst(rst),
    .clk(cpu_clk),
    .load(!cur_b_comp_out[1]),
    .D(cur_b_reg_q),
    .Q(cur_b_prev_q)
);

Comparator #(.WIDTH(8)
) current_blue_comparator (
    .in({cur_b_reg_q, cur_b_prev_q}),
    .out(cur_b_comp_out)
);

REGISTER #(.WIDTH(8)
) saved_red_reg (
    .rst(rst),
    .clk(cpu_clk),
    .load(sav_r_reg_cs),
    .D(DataBus[7:0]),
    .Q(sav_r_reg_q)
);

REGISTER #(.WIDTH(8)
) saved_green_reg (
    .rst(rst),
    .clk(cpu_clk),
    .load(sav_g_reg_cs),
    .D(DataBus[7:0]),
    .Q(sav_g_reg_q)
);

REGISTER #(.WIDTH(8)
) saved_blue_reg (
    .rst(rst),
    .clk(cpu_clk),
    .load(sav_b_reg_cs),
    .D(DataBus[7:0]),
    .Q(sav_b_reg_q)
);

MUX #(
    .WIDTH(8),
    .INPUTS(2)
) r_led_source_mux (
    .select(ext_switch),
    .in({cur_r_reg_q, sav_r_reg_q}),
    .out(r_mux_out)
);

REGISTER #(.WIDTH(8)
) prev_r_mux_register (
    .rst(rst),
    .clk(cpu_clk),
    .load(!r_mux_comp_out),
    .D(r_mux_out),
    .Q(prev_r_mux_out)
);

Comparator #(.WIDTH(8)
) r_mux_comparator (
    .in({r_mux_out, prev_r_mux_out}),
    .out(r_mux_comp_out)
);

MUX #(
    .WIDTH(8),
    .INPUTS(2)
) g_led_source_mux (
    .select(ext_switch),
    .in({cur_g_reg_q, sav_g_reg_q}),
    .out(g_mux_out)
);

REGISTER #(.WIDTH(8)
) prev_g_mux_register (
    .rst(rst),
    .clk(cpu_clk),
    .load(!g_mux_comp_out),
    .D(g_mux_out),
    .Q(prev_g_mux_out)
);

Comparator #(.WIDTH(8)
) g_mux_comparator (
    .in({g_mux_out, prev_g_mux_out}),
    .out(g_mux_comp_out)
);

MUX #(
    .WIDTH(8),
    .INPUTS(2)
) b_led_source_mux (
    .select(ext_switch),
    .in({cur_b_reg_q, sav_b_reg_q}),
    .out(b_mux_out)
);

REGISTER #(.WIDTH(8)
) prev_b_mux_register (
    .rst(rst),
    .clk(cpu_clk),
    .load(!b_mux_comp_out),
    .D(b_mux_out),
    .Q(prev_b_mux_out)
);

Comparator #(.WIDTH(8)
) b_mux_comparator (
    .in({b_mux_out, prev_b_mux_out}),
    .out(b_mux_comp_out)
);

QuadratureDecoder #(.BUS_WIDTH(32)
) quad_decoder (
    .clk(cpu_clk), 
    .rst(rst), 
    .oe(quad_decode_cs), 
    .we(quad_we),
    .ext_phase_a(ext_phase_a), 
    .ext_phase_b(ext_phase_b),
    .direction(quad_dir),
    .data(DataBus)
);

TRIBUFFER #(.WIDTH(32)
) button_input_buffer (
    .oe(btn_cs),
    .in({31'b0, ext_button}),
    .out(DataBus)
);

PWM_Driver PWM_L_R (
    .sys_clk(clk100Mhz),
    .reset(rst),
    .load(pwm_l_r_cs),
    .data({cur_r_reg_q, `PWM_PERIOD}),
    .signal(LED_L[2])
);

PWM_Driver PWM_L_G (
    .sys_clk(clk100Mhz),
    .reset(rst),
    .load(pwm_l_g_cs),
    .data({cur_g_reg_q, `PWM_PERIOD}),
    .signal(LED_L[1])
);

PWM_Driver PWM_L_B (
    .sys_clk(clk100Mhz),
    .reset(rst),
    .load(pwm_l_b_cs),
    .data({cur_b_reg_q, `PWM_PERIOD}),
    .signal(LED_L[0])
);

PWM_Driver PWM_R_R (
    .sys_clk(clk100Mhz),
    .reset(rst),
    .load(pwm_r_r_cs),
    .data({r_mux_out, `PWM_PERIOD}),
    .signal(LED_R[2])
);

PWM_Driver PWM_R_G (
    .sys_clk(clk100Mhz),
    .reset(rst),
    .load(pwm_r_g_cs),
    .data({g_mux_out, `PWM_PERIOD}),
    .signal(LED_R[1])
);

PWM_Driver PWM_R_B (
    .sys_clk(clk100Mhz),
    .reset(rst),
    .load(pwm_r_b_cs),
    .data({b_mux_out, `PWM_PERIOD}),
    .signal(LED_R[0])
);
// ==================================
//// Registers
// ==================================
// ==================================
//// Behavioral Block
// ==================================

endmodule