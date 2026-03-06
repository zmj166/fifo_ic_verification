// ============================================================================
// 文件名: fifo_random_test.sv
// 描述:   随机并发测试
// 场景:   写和读同时进行，随机延迟，压力测试
// ============================================================================

`include "fifo_base_test.sv"

class fifo_random_test #(parameter DATA_WIDTH = 8, parameter ADDR_WIDTH = 4)
    extends fifo_base_test #(DATA_WIDTH, ADDR_WIDTH);

    function new(string name,
                 virtual fifo_write_if #(DATA_WIDTH) w_vif,
                 virtual fifo_read_if  #(DATA_WIDTH) r_vif);
        super.new(name, w_vif, r_vif);
    endfunction

    virtual task run_sequences();
        fifo_back2back_seq #(DATA_WIDTH) b2b_seq;

        $display("[%s] Random Concurrent Test: 64 transactions", name);

        b2b_seq = new("b2b_seq", env.wr_drv_mbx, env.rd_drv_mbx, 64);
        b2b_seq.run();
    endtask

endclass : fifo_random_test
