// =============================================================
//  MODULE: fifo_assertions
//  Kiểm tra bất biến (invariants) của FIFO mỗi posedge clk.
//  Được instantiate trong fifo_tb như một sub-module riêng.
//
//  Lý do tách thành module riêng:
//    • Assertions dùng $past() → cần clock sensitivity → phải trong module
//    • Tách biệt assertion logic khỏi testbench top
//    • Có thể dùng với `bind` để check DUT trực tiếp (nâng cao)
//
//  ASSERT 1 — Mutex:
//    full && empty không được = 1 cùng lúc (bất biến vật lý)
//
//  ASSERT 2 — Overflow protection:
//    Nếu cycle trước: full=1 && wr_en=1 && rd_en=0
//    → Cycle này: full phải = 1 (FIFO không tự co lại)
//
//  ASSERT 3 — Underflow protection:
//    Nếu cycle trước: empty=1 && rd_en=1 && wr_en=0
//    → Cycle này: empty phải = 1 (FIFO không tự có data)
//
//  Dùng $past(signal) để nhìn lại giá trị cycle trước.
// =============================================================

module fifo_assertions (
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic rd_en,
    input logic full,
    input logic empty
);

    always @(posedge clk) begin
        if (rst_n) begin

            // --------------------------------------------------
            // ASSERT 1: Mutual exclusion
            //   full và empty không thể = 1 đồng thời
            // --------------------------------------------------
            assert (!(full && empty))
                else $error(
                    "[ASSERT 1 FAIL] full && empty = 1 cùng lúc!");

            // --------------------------------------------------
            // ASSERT 2: Overflow protection
            //   $past(x) = giá trị của x ở 1 cycle trước
            // --------------------------------------------------
            if ($past(full) && $past(wr_en) && !$past(rd_en))
                assert (full)
                    else $error(
                        "[ASSERT 2 FAIL] Overflow! Write vào FIFO full → full phải giữ nguyên ở cycle sau");

            // --------------------------------------------------
            // ASSERT 3: Underflow protection
            // --------------------------------------------------
            if ($past(empty) && $past(rd_en) && !$past(wr_en))
                assert (empty)
                    else $error(
                        "[ASSERT 3 FAIL] Underflow! Read từ FIFO empty → empty phải giữ nguyên ở cycle sau");

        end
    end

endmodule
