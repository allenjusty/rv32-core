// Compares every RTL record with the next line of the expected (Spike) trace.
// Masked: the rd value of reads of mcycle(h), minstret(h), mip and marchid, and the new
// value written to a counter or mip (spec section 8).
// On the first mismatch it prints the last 20 records of both sides and stops the test.
class spike_scoreboard extends uvm_subscriber #(core_rec);
  `uvm_component_utils(spike_scoreboard)

  core_cfg cfg;
  string   exp[$];            // expected records, in order
  string   hist_exp[$], hist_got[$];
  int      idx;               // next expected record
  int      n_masked;
  bit      failed;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    int fd;
    string line;
    if (!uvm_config_db#(core_cfg)::get(this, "", "cfg", cfg)) `uvm_fatal("NOCFG", "no cfg")
    if (!cfg.compare) begin
      `uvm_info("SB", "Spike compare off for this test (self-checking program)", UVM_LOW)
      return;
    end
    fd = $fopen(cfg.exp_trace, "r");
    if (fd == 0) `uvm_fatal("NOEXP", $sformatf("cannot open expected trace '%s' (+EXP=)", cfg.exp_trace))
    while ($fgets(line, fd)) begin
      // strip the newline
      while (line.len() > 0 && (line[line.len()-1] == "\n" || line[line.len()-1] == "\r"))
        line = line.substr(0, line.len() - 2);
      if (line.len() > 0) exp.push_back(line);
    end
    $fclose(fd);
    `uvm_info("SB", $sformatf("%0d expected records from %s", exp.size(), cfg.exp_trace), UVM_LOW)
  endfunction

  // A CSR read whose value never matches Spike
  static function bit masked_read(bit [31:0] insn);
    bit [11:0] csr = insn[31:20];
    if (insn[6:0] != 7'h73 || insn[14:12] == 3'b000 || insn[14:12] == 3'b100) return 0;
    return csr inside {12'hB00, 12'hB80, 12'hB02, 12'hB82, 12'h344, 12'hF12};
  endfunction

  // Mask the rd value in a record string: "R pc insn rd:val ..." -> "R pc insn rd:(masked) ..."
  function string mask(string s);
    string f[$];
    string tok;
    int    p;
    bit [31:0] insn;
    if (s.len() == 0 || s[0] != "R") return s;
    // split on spaces
    tok = "";
    for (int i = 0; i < s.len(); i++) begin
      if (s[i] == " ") begin f.push_back(tok); tok = ""; end
      else tok = {tok, s[i]};
    end
    f.push_back(tok);
    if (f.size() < 4) return s;
    insn = f[2].atohex();
    if (masked_read(insn) && f[3] != "-") begin
      p = 0;
      while (p < f[3].len() && f[3][p] != ":") p++;
      f[3] = {f[3].substr(0, p - 1), ":(masked)"};
      n_masked++;
    end
    // the new value of a counter or mip depends on its old value: mask it too
    if (masked_read(insn) && insn[31:20] inside {12'hB00, 12'hB80, 12'hB02, 12'hB82, 12'h344} &&
        f.size() > 5 && f[5] != "-") begin
      f[5] = {f[5].substr(0, 2), ":(masked)"};
    end
    s = f[0];
    for (int i = 1; i < f.size(); i++) s = {s, " ", f[i]};
    return s;
  endfunction

  function void write(core_rec t);
    string got = t.convert2string();
    string e;
    // The Spike trace ends with the store to tohost; what retires after it (the end
    // loop, while the test drains) is not compared.
    if (!cfg.compare || failed || idx >= exp.size()) return;
    hist_got.push_back(got);
    if (hist_got.size() > 20) void'(hist_got.pop_front());
    e = exp[idx++];
    hist_exp.push_back(e);
    if (hist_exp.size() > 20) void'(hist_exp.pop_front());
    if (mask(e) != mask(got))
      fail($sformatf("record %0d\n  expected (Spike): %s\n  got      (RTL)  : %s", idx - 1, e, got));
  endfunction

  function void fail(string msg);
    string s = "";
    failed = 1;
    foreach (hist_exp[i]) s = {s, "\n  spike: ", hist_exp[i]};
    s = {s, "\n  ---"};
    foreach (hist_got[i]) s = {s, "\n  rtl  : ", hist_got[i]};
    `uvm_error("MISMATCH", {msg, "\nLast records:", s})
  endfunction

  function bit all_matched();
    return !cfg.compare || (!failed && idx == exp.size());
  endfunction

  function void check_phase(uvm_phase phase);
    if (cfg.compare && !failed && idx != exp.size())
      `uvm_error("SB", $sformatf("RTL stopped after %0d records, Spike trace has %0d (next: %s)",
                                 idx, exp.size(), exp[idx]))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("%0d of %0d records matched (%0d masked CSR reads)",
                              failed ? idx - 1 : idx, exp.size(), n_masked), UVM_LOW)
  endfunction
endclass
