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
    t = t.replace("\r\n", "\n");
    t = t.replace('\r', "\n");
    let esc_misc = Regex::new(r"\x1B[=><]").unwrap();
    t = esc_misc.replace_all(&t, "").to_string();
    t = strip_backspaces(&t);
    t = ctrl_re.replace_all(&t, "").to_string();
    t.trim().to_string()
}

fn hook_regexes() -> Vec<Regex> {
    // bash ASCII divider containing the literal message
    // Avoid using \s to keep unicode-perl feature unnecessary; use explicit ASCII whitespace
    let bash_ts = Regex::new(r"^-+[ \t]+Shell log started\.[ \t]+-+$").unwrap();
    // zsh flexible: optional rounded or right arrow around the literal message
    let zsh_ts = Regex::new(r"^[ \t]*(?:[ \t]*)?Shell log started\.(?:[ \t]*|[ \t]*)?[ \t]*$").unwrap();
    vec![zsh_ts, bash_ts]
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
    let mut cmd_idx = None;
    for (i, ln) in block.iter().enumerate() { if !ln.trim().is_empty() { cmd_idx = Some(i); break; } }
    let i = cmd_idx?;

    // Helper: does a line contain 'wtf' not followed by specific options?
    fn contains_wtf_without_help_opts(line: &str) -> bool {
        // Find 'wtf' as a whole word anywhere in the line, capture what's after it on the same line
        let re_wtf = Regex::new(r"(?i)\bwtf\b(.*)$").unwrap();
        if let Some(caps) = re_wtf.captures(line) {
            let rest = caps.get(1).map(|m| m.as_str()).unwrap_or("");
            // If the immediate args are one of the allowed info flags, do NOT treat specially
            let re_allowed = Regex::new(r"(?i)^[ \t]*(--help|-h|-V|--version|--config|--update|--uninstall)\b").unwrap();
            !re_allowed.is_match(rest)
        } else {
            false
        }
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
    let cleaned = clean_text(&raw);
    let lines: Vec<String> = cleaned.lines().map(|s| s.to_string()).collect();
    let blocks = extract_blocks_by_hooks(&lines);
    let mut pairs: Vec<(String, String)> = Vec::new();
    for blk in blocks { if let Some(p) = block_to_cmd_out(&blk) { pairs.push(p); } }
    let pairs = filter_wtf_commands_inline(&pairs);
    let len = pairs.len();
    let start = len.saturating_sub(n);
    Ok(pairs[start..].to_vec())
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
