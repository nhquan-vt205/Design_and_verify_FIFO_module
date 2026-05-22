// =============================================================
//  MODULE: fifo_coverage
//  Covergroup đo độ phủ chức năng (functional coverage).
//  Được instantiate trong fifo_tb như một sub-module riêng.
//
//  Lý do tách thành module riêng (không để trong class):
//    • Covergroup trong SV cần truy cập signals → bắt buộc trong module
//    • Tách biệt coverage logic khỏi testbench top
//    • Dễ tái dùng cho các DUT khác có cùng interface
//
//  Truy cập từ top-level: u_cov.cg_inst.get_coverage()
//
//  Điểm đo:
//    cp_ops          — 4 loại operation: wr_only, rd_only, both, idle
//    cp_full         — trạng thái full (0 hoặc 1)
//    cp_empty        — trạng thái empty (0 hoặc 1)
//    cp_almost_full  — trạng thái gần đầy
//    cp_almost_empty — trạng thái gần rỗng
//    cx_ops_x_full   — cross: operation × full state
//    cx_ops_x_empty  — cross: operation × empty state
// =============================================================

module fifo_coverage (
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic rd_en,
    input logic full,
    input logic empty,
    input logic almost_full,
    input logic almost_empty
);

    covergroup fifo_cg @(posedge clk iff rst_n);

        // Loại thao tác trong mỗi cycle
        cp_ops: coverpoint {wr_en, rd_en} {
            bins wr_only = {2'b10};    // chỉ write
            bins rd_only = {2'b01};    // chỉ read
            bins both    = {2'b11};    // đọc+ghi cùng lúc
            bins idle    = {2'b00};    // không làm gì
        }

        // Trạng thái biên của FIFO
        cp_full:         coverpoint full;
        cp_empty:        coverpoint empty;
        cp_almost_full:  coverpoint almost_full;
        cp_almost_empty: coverpoint almost_empty;

        // Cross coverage: operation nào xảy ra ở trạng thái nào
        // → phát hiện: write khi full? read khi empty?
        cx_ops_x_full:  cross cp_ops, cp_full;
        cx_ops_x_empty: cross cp_ops, cp_empty;

    endgroup

    fifo_cg cg_inst = new();

endmodule
