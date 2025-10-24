mod config;
mod logs;
mod llm;

use clap::{Parser};
use std::io::{self, Write};
use std::process::Command;

#[derive(Parser, Debug)]
#[command(name = "wtf", version, about = "Fix your previous shell command using an LLM")] 
struct Cli {
    /// Configure Withefuck
    #[arg(long)]
    config: bool,
    /// View shell logs
    #[arg(long)]
    logs: bool,
    /// Update Withefuck
    #[arg(long)]
    update: bool,
    /// Uninstall Withefuck
    #[arg(long)]
    uninstall: bool,
}

fn build_prompt(context: &str) -> String {
    format!(
        "You are given a shell session log. Your task: output ONE corrected shell command that fixes the last command's error.\n\n\
         Strict requirements:\n\
         - Correct flags and syntax (add missing leading dashes for short flags).\n\
         - Keep the user's intent and minimal changes.\n\
         - Quote paths/args with spaces.\n\
         - Output only the command, no comments, no backticks, no code fences.\n\
         - If nothing needs fixing or it's ambiguous, output exactly: None\n\n\
         Context:\n{}\n",
        context
    )
}

fn previous_commands_context(n: usize) -> String {
    match logs::get_last_n_commands(n) {
        Ok(pairs) => {
            let parts: Vec<String> = pairs.into_iter().map(|(c, o)| {
                if c.is_empty() { o } else { format!("{}\n\n{}", c, o) }
            }).collect();
            parts.join("\n\n")
        }
        Err(_) => String::new(),
    }
}

fn shell_eval(command: &str) -> i32 {
    // Execute via user's shell if possible, else fallback to sh -lc
    let user_shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
    let status = Command::new(user_shell)
        .arg("-lc")
        .arg(command)
        .status();
    match status { Ok(s) => s.code().unwrap_or(1), Err(_) => 1 }
}

fn main() {
    let cli = Cli::parse();

    if cli.config {
        if let Err(e) = config::interactive_config() { eprintln!("{}", e); std::process::exit(1); }
        return;
    }

    // Load config (needed for history_count used by --logs)
    let cfg = match config::load_config() {
        Ok(c) => c,
        Err(e) => { eprintln!("{}", e); std::process::exit(1) }
    };
    if let Err(e) = cfg.validate() {
        eprintln!("{}", e); std::process::exit(1);
    }

    if cli.logs {
        let hist_n = if cfg.history_count == 0 { 5 } else { cfg.history_count };
        logs::print_last_commands(hist_n);
        return;
    }

    let hist_n = if cfg.history_count == 0 { 5 } else { cfg.history_count };
    let context = previous_commands_context(hist_n);
    let prompt = build_prompt(&context);
    let client = llm::LlmClient::new(
        cfg.api_key.unwrap().to_string(),
        cfg.api_endpoint.unwrap().to_string(),
        cfg.model.unwrap().to_string(),
        cfg.temperature,
    );

    match client.suggest(&prompt) {
        Ok(Some(suggestion)) => {
            // Interactive confirm (single line, single stream to avoid reordering)
            eprint!("{} ", suggestion);
            let colored = if atty::is(atty::Stream::Stderr)
                && std::env::var("WTF_NO_COLOR").is_err()
                && std::env::var("NO_COLOR").is_err()
            {
                format!("[\u{001b}[32menter\u{001b}[0m/\u{001b}[31mctrl+c\u{001b}[0m]")
            } else {
                "[enter/ctrl+c]".to_string()
            };
            eprint!("{}", colored);
            io::stderr().flush().ok();
            let mut line = String::new();
            if io::stdin().read_line(&mut line).is_err() { return; }
            if line.trim().is_empty() {
                // Move to a new line before executing to keep output clean
                eprintln!("");
                let code = shell_eval(&suggestion);
                std::process::exit(code);
            }
        }
        Ok(None) => {
            eprintln!("Unable to fix the command or no fix needed.");
        }
        Err(e) => {
            eprintln!("{}", e);
        }
    }
}
