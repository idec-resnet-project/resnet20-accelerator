`timescale 1ns/1ps
// 방향과 무관한 데이터·시퀀스·스코어보드 타입은 한 번만 정의한다.
package axi_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "axi_item.svh"
    `include "axi_observation.svh"
    `include "axi_sequence.svh"
    `include "axi_sequencer.svh"
    `include "axi_driver.svh"
    `include "axi_monitor.svh"
    `include "axi_agent.svh"
    `include "axi_scoreboard.svh"
    `include "axi_env.svh"
    `include "axi_test.svh"

endpackage
