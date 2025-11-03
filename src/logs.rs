use regex::Regex;
use std::env;
use std::fs;
use std::path::PathBuf;

const LOG_DIR_NAME: &str = ".shell_logs";

fn home_dir() -> PathBuf { dirs::home_dir().unwrap_or_else(|| PathBuf::from("~")) }

fn log_dir() -> PathBuf { home_dir().join(LOG_DIR_NAME) }

fn latest_log_path() -> Result<PathBuf, String> {
    if let Ok(p) = env::var("WTF_TYPESCRIPT") { let pb = PathBuf::from(p); if pb.exists() { return Ok(pb); } }
    let mut files: Vec<PathBuf> = fs::read_dir(log_dir())
        .map_err(|_| "No script log found. Please run some commands first.".to_string())?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.file_name().and_then(|s| s.to_str()).map(|s| s.starts_with("typescript-")).unwrap_or(false))
        .collect();
    files.sort();
    files.last().cloned().ok_or_else(|| "No script log found. Please run some commands first.".to_string())
}

fn strip_backspaces(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        if ch == '\u{0008}' { out.pop(); } else { out.push(ch); }
    }
    out
}

fn clean_text(text: &str) -> String {
    // CSI: ESC [ ...
    let csi_re = Regex::new(r"\x1B\[[0-?]*[ -/]*[@-~]").unwrap();
    // OSC: ESC ] ... BEL or ST (ESC \\
    let osc_re = Regex::new(r"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)").unwrap();
    // Other single-char controls
    let ctrl_re = Regex::new(r"[\x00-\x08\x0b\x0c\x0e-\x1f]").unwrap();

    let mut t = csi_re.replace_all(text, "").to_string();
    t = osc_re.replace_all(&t, "").to_string();
    // Remove other ESC-prefixed sequences commonly seen in terminals
    // - ESC Fe (single final byte in @-Z\\^_)
    let esc_single = Regex::new(r"\x1B[@-Z\\^_]").unwrap();
    t = esc_single.replace_all(&t, "").to_string();
    // - ESC with one intermediate (0x20-0x2F) and a final byte (0x40-0x7E), e.g. ESC(B, ESC)0, ESC#8, ESC%G
    let esc_two = Regex::new(r"\x1B[ -/][@-~]").unwrap();
    t = esc_two.replace_all(&t, "").to_string();
    t = t.replace("\r\n", "\n");
    t = t.replace('\r', "\n");
    let esc_misc = Regex::new(r"\x1B[=><]").unwrap();
    t = esc_misc.replace_all(&t, "").to_string();
    // Remove visible return glyphs that appear in some logs
    t = t.replace('⏎', "");
    t = strip_backspaces(&t);
    t = ctrl_re.replace_all(&t, "").to_string();
    t.trim().to_string()
}

fn clean_line(line: &str) -> String {
    // Per-line cleaner mirroring clean_text but preserving line structure
    let csi_re = Regex::new(r"\x1B\[[0-?]*[ -/]*[@-~]").unwrap();
    let osc_re = Regex::new(r"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)").unwrap();
    let esc_single = Regex::new(r"\x1B[@-Z\\^_]").unwrap();
    let esc_two = Regex::new(r"\x1B[ -/][@-~]").unwrap();
    let esc_misc = Regex::new(r"\x1B[=><]").unwrap();
    let ctrl_re = Regex::new(r"[\x00-\x08\x0b\x0c\x0e-\x1f]").unwrap();

    let mut s = csi_re.replace_all(line, "").to_string();
    s = osc_re.replace_all(&s, "").to_string();
    s = esc_single.replace_all(&s, "").to_string();
    s = esc_two.replace_all(&s, "").to_string();
    s = esc_misc.replace_all(&s, "").to_string();
    s = s.replace('⏎', "");
    s = strip_backspaces(&s);
    s = ctrl_re.replace_all(&s, "").to_string();
    s
}

fn hook_regexes() -> Vec<Regex> {
    // bash ASCII divider containing the literal message
    // Avoid using \s to keep unicode-perl feature unnecessary; use explicit ASCII whitespace
    let bash_ts = Regex::new(r"^-+[ \t]+Shell log started\.[ \t]+-+$").unwrap();
    // zsh flexible: optional rounded or right arrow around the literal message
    let zsh_ts = Regex::new(r"^[ \t]*(?:[ \t]*)?Shell log started\.(?:[ \t]*|[ \t]*)?[ \t]*$").unwrap();
    // fish fallback: powerline glyph may be replaced by '?' or omitted after cleaning.
    // Accept the plain message optionally followed by any non-word, non-space ASCII symbol(s).
    let fish_ts = Regex::new(r"^[ \t]*Shell log started\.[ \t]*(?:[^A-Za-z0-9_ \t].*)?$").unwrap();
    // ultimate fallback: any line containing the literal text (ASCII, case-sensitive to avoid unicode-case feature)
    let generic_ts = Regex::new(r"Shell log started\.").unwrap();
    vec![zsh_ts, bash_ts, fish_ts, generic_ts]
}

fn extract_blocks_by_hooks(lines: &[String]) -> Vec<Vec<String>> {
    let ts = hook_regexes();
    let mut idx = Vec::new();
    for (i, ln) in lines.iter().enumerate() {
        if ts.iter().any(|r| r.is_match(ln.as_str())) { idx.push(i); }
    }
    let mut blocks = Vec::new();
    if idx.len() < 2 { return blocks; }
    for w in idx.windows(2) {
        let a = w[0]; let b = w[1];
        let seg = lines[a+1..b].to_vec();
        blocks.push(seg);
    }
    blocks
}

fn block_to_cmd_out(block: &[String]) -> Option<(String, String)> {
    if block.is_empty() { return None; }
    // helpers for noise/prompt detection similar to Python version
    fn is_noise_line(ln: &str) -> bool { ln.replace('⏎', "").trim().is_empty() }
    fn looks_like_prompt(ln: &str) -> bool {
        let s = ln.trim();
        (s.contains('@')) && (s.ends_with('#') || s.ends_with('$') || s.ends_with("# ") || s.ends_with("$ "))
    }

    let mut cmd_idx: Option<usize> = None;
    for (i, ln) in block.iter().enumerate() {
        let s = ln.trim();
        if s.is_empty() || is_noise_line(s) || looks_like_prompt(s) { continue; }
        // prefer a line that looks like a real command
        if s.len() >= 2 || s.chars().any(|ch| !ch.is_ascii_alphabetic()) {
            cmd_idx = Some(i);
            break;
        }
    }
    let i = cmd_idx?;

    // Helper: does a line contain 'wtf' not followed by specific options?
    fn contains_wtf_without_help_opts(line: &str) -> bool {
        // ASCII-only detection to avoid requiring unicode regex features.
        // Find 'wtf' as a whole word and inspect the immediate rest of the line.
        let lower = line.to_ascii_lowercase();
        let bytes = lower.as_bytes();
        let target = b"wtf";

        // helper: ASCII word char
        fn is_word(b: u8) -> bool { b.is_ascii_alphanumeric() || b == b'_' }

        let mut i = 0;
        while i + target.len() <= bytes.len() {
            if &bytes[i..i+target.len()] == target {
                let left_ok = i == 0 || !is_word(bytes[i-1]);
                let j = i + target.len();
                let right_ok = j == bytes.len() || !is_word(bytes[j]);
                if left_ok && right_ok {
                    // rest of original string starting at j
                    let rest = &lower[j..];
                    let rest_trim = rest.trim_start_matches([' ', '\t']);
                    // allowed leading flags that should NOT trigger special handling
                    let allowed = ["--help","-h","-v","-V","--version","--config","--update","--uninstall"]; // accept both -v and -V
                    let is_allowed = allowed.iter().any(|p| rest_trim.starts_with(p));
                    return !is_allowed;
                }
                i += 1; // continue searching after this position
            } else {
                i += 1;
            }
        }
        false
    }

    // Start building command and decide where output begins
    let mut cmd = block[i].to_string();
    let mut out_start = i + 1;
    if out_start < block.len() {
        let next_line = &block[out_start];
        // If the next line contains 'wtf' (anywhere) and isn't followed by help/version/config flags,
        // treat it as part of the command line (to support zsh themes that wrap prompts).
        if contains_wtf_without_help_opts(next_line) {
            cmd.push('\n');
            cmd.push_str(next_line);
            out_start += 1;
        }
    }

    let out = block[out_start..].join("\n").trim().to_string();
    Some((cmd, out))
}

fn filter_wtf_commands_inline(results: &[(String, String)]) -> Vec<(String, String)> {
    let tail_re = Regex::new(r"(wtf(?:[ \t]+--logs)?)[ \t]*$").unwrap();
    let mut filtered: Vec<(String, String)> = Vec::new();
    for (cmd, out) in results.iter() {
        let s = cmd.trim();
        if let Some(m) = tail_re.captures(s) { 
            let tail = m.get(1).unwrap().as_str().to_lowercase();
            if tail == "wtf --logs" { continue; }
            if tail == "wtf" {
                if let Some(last) = filtered.last_mut() {
                    if last.1.is_empty() { last.1 = out.clone(); } else { last.1.push('\n'); last.1.push_str(out); }
                } else {
                    filtered.push((String::new(), out.clone()));
                }
                continue;
            }
        }
        filtered.push((cmd.clone(), out.clone()));
    }
    filtered
}

pub fn get_last_n_commands(n: usize) -> Result<Vec<(String, String)>, String> {
    let path = latest_log_path()?;
    let raw = fs::read_to_string(&path).map_err(|e| format!("Failed to read log: {e}"))?;

    // Work per-line to keep raw/clean alignment
    let raw_lines: Vec<&str> = raw.lines().collect();
    let cleaned_lines: Vec<String> = raw_lines.iter().map(|l| clean_line(l)).collect();

    // Find hook indices on cleaned lines
    let ts = hook_regexes();
    let mut idx: Vec<usize> = Vec::new();
    for (i, ln) in cleaned_lines.iter().enumerate() { if ts.iter().any(|r| r.is_match(ln.as_str())) { idx.push(i); } }

    let mut results: Vec<(String, String)> = Vec::new();
    if idx.len() >= 2 {
        let osc_title_re = Regex::new(r"\x1B\]([02]);([^\x07\x1B]*)(?:\x07|\x1B\\)").unwrap();
        for w in idx.windows(2) {
            let a = w[0];
            let b = w[1];
            let blk_clean: Vec<String> = cleaned_lines[a+1..b].to_vec();
            let blk_raw = raw_lines[a+1..b].join("\n");

            if let Some((mut cmd, mut out)) = block_to_cmd_out(&blk_clean) {
                // Override using last OSC title and compute output strictly after it
                let mut last_cap: Option<regex::Captures> = None;
                for cap in osc_title_re.captures_iter(&blk_raw) { last_cap = Some(cap); }
                if let Some(cap) = last_cap {
                    let m0 = cap.get(0).unwrap();
                    let end = m0.end();
                    let title_txt = cap.get(2).map(|m| m.as_str()).unwrap_or("");
                    let better = cmd_from_title(title_txt);
                    if !better.is_empty() { cmd = better; }

                    let raw_after = &blk_raw[end..];
                    let out_lines: Vec<&str> = raw_after.lines().collect();
                    let mut filtered: Vec<String> = Vec::new();
                    for l in out_lines {
                        let s = clean_line(l).trim().to_string();
                        if s.is_empty() { continue; }
                        if !cmd.is_empty() && (s == cmd || (s.len() < cmd.len() && cmd.starts_with(&s))) { continue; }
                        filtered.push(s);
                    }
                    out = filtered.join("\n").trim().to_string();
                }
                results.push((cmd, out));
            }
        }
    }

    if results.is_empty() {
        // Fallback to old path
        let cleaned = clean_text(&raw);
        let lines: Vec<String> = cleaned.lines().map(|s| s.to_string()).collect();
        let blocks = extract_blocks_by_hooks(&lines);
        for blk in blocks { if let Some(p) = block_to_cmd_out(&blk) { results.push(p); } }
    }

    let results = filter_wtf_commands_inline(&results);
    let len = results.len();
    let start = len.saturating_sub(n);
    Ok(results[start..].to_vec())
}

fn cmd_from_title(title: &str) -> String {
    // Extract command from title like "[host] cmd args [cwd]"
    if title.is_empty() { return String::new(); }
    let mut s = title.trim().to_string();
    if let Some(caps) = Regex::new(r"^\[[^\]]*\][ \t]+(.*)$").unwrap().captures(&s) {
        s = caps.get(1).unwrap().as_str().to_string();
    }
    let mut tokens: Vec<&str> = s.split_whitespace().collect();
    if tokens.is_empty() { return String::new(); }
    if let Some(last) = tokens.last() {
        if *last == "~" || last.starts_with('/') || last.starts_with('~') { tokens.pop(); }
    }
    tokens.join(" ")
}

pub fn print_last_commands(n: usize) {
    match get_last_n_commands(n) {
        Ok(cmds) => {
            if cmds.len() == 1 { println!("Last command and its output:\n"); }
            else { println!("Last {} commands and their outputs:\n", cmds.len()); }
            for (cmd, output) in cmds {
                println!("$ {}", cmd);
                if output.is_empty() { println!("(No output)\n"); } else { println!("{}\n", output); }
            }
        }
        Err(e) => {
            eprintln!("Warning: {}", e);
        }
    }
}
