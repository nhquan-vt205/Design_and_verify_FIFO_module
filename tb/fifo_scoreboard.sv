// =============================================================
//  CLASS: fifo_scoreboard
//  Nhận fifo_result từ Monitor qua mailbox mon2sb.
//  Dùng queue SystemVerilog ($) làm reference model của FIFO thực.
//  So sánh dout thực với giá trị kỳ vọng → báo PASS/FAIL.
//
//  Tách biệt hoàn toàn với Monitor:
//    - Scoreboard KHÔNG biết về clock, DUT signals
//    - Chỉ nhận kết quả đã được Monitor trừu tượng hóa thành fifo_result
//    - Reference model (ref_q) phản ánh chính xác hành vi FIFO
//
//  Reference model logic:
//    WRITE_EVT → push_back(data) vào ref_q  (giống DUT ghi vào mem)
//    READ_EVT  → pop_front() từ ref_q        (giống DUT đọc theo FIFO order)
//              → so sánh với data thực tế từ Monitor
// =============================================================

class fifo_scoreboard;

    mailbox #(fifo_result) mon2sb;

    // Reference model — queue SV mirroring FIFO thực tế
    logic [7:0] ref_q [$];

    int pass_cnt;
    int fail_cnt;
    int wr_cnt;
    int rd_cnt;

    function new(mailbox #(fifo_result) mb);
        mon2sb   = mb;
        pass_cnt = 0;
        fail_cnt = 0;
        wr_cnt   = 0;
        rd_cnt   = 0;
    endfunction

    // ----------------------------------------------------------
    // run() — vòng lặp xử lý vô tận
    //   Gọi trong: fork sb.run(); join_none
    // ----------------------------------------------------------
    task run();
        fifo_result res;

        forever begin
            mon2sb.get(res);    // chặn đến khi Monitor gửi kết quả

            case (res.evt_type)

                // Write event: cập nhật reference model
                fifo_result::WRITE_EVT: begin
                    ref_q.push_back(res.data);
                    wr_cnt++;
                end

                // Read event: so sánh với đầu queue
                fifo_result::READ_EVT: begin
                    logic [7:0] expected;
                    rd_cnt++;
                    if (ref_q.size() == 0) begin
                        $warning("[SB] Read event nhưng ref_q đang rỗng!");
                    end else begin
                        expected = ref_q.pop_front();
                        if (res.data === expected) begin
                            pass_cnt++;
                            $display("[SB PASS] exp=0x%02h  got=0x%02h",
                                     expected, res.data);
                        end else begin
                            fail_cnt++;
                            $error("[SB FAIL] exp=0x%02h  got=0x%02h",
                                   expected, res.data);
                        end
                    end
                end

            endcase
        end
    endtask

    // In kết quả tổng kết cuối simulation
    function void report();
        $display("");
        $display("╔══════════════════════════════════════╗");
        $display("║         SCOREBOARD REPORT            ║");
        $display("╠══════════════════════════════════════╣");
        $display("║  Writes  : %-5d                      ║", wr_cnt);
        $display("║  Reads   : %-5d                      ║", rd_cnt);
        $display("║  PASS    : %-5d                      ║", pass_cnt);
        $display("║  FAIL    : %-5d                      ║", fail_cnt);
        $display("╠══════════════════════════════════════╣");
        if (fail_cnt == 0)
            $display("║  >>> ALL CHECKS PASSED ✓             ║");
        else
            $display("║  >>> %0d CHECKS FAILED ✗              ║", fail_cnt);
        $display("╚══════════════════════════════════════╝");
    endfunction

endclass
