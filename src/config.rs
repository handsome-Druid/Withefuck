use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use serde::{Deserialize, Deserializer, Serialize};

pub const WTF_CONFIG_FILENAME: &str = "wtf.json";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Config {
    pub api_key: Option<String>,
    pub api_endpoint: Option<String>,
    pub model: Option<String>,
    #[serde(default = "default_history_count", deserialize_with = "de_usize_flexible")]
    pub history_count: usize,
    #[serde(default, deserialize_with = "de_f32_flexible")]
    pub temperature: f32,
}

fn default_history_count() -> usize { 5 }

impl Config {
    pub fn validate(&self) -> Result<(), String> {
        if self.api_key.as_deref().unwrap_or("").is_empty()
            || self.api_endpoint.as_deref().unwrap_or("").is_empty()
            || self.model.as_deref().unwrap_or("").is_empty()
        {
            return Err("Incomplete configuration. Please run 'wtf --config' to set up.".into());
        }
        if self.history_count == 0 || self.history_count > 100 {
            return Err("history_count must be between 1 and 100".into());
        }
        if !(0.0..=1.0).contains(&self.temperature) {
            return Err("temperature must be between 0.0 and 1.0".into());
        }
        Ok(())
    }
}

fn de_usize_flexible<'de, D>(deserializer: D) -> Result<usize, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::{Error, Unexpected};
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum UsizeOrString { U(usize), S(String) }
    match UsizeOrString::deserialize(deserializer)? {
        UsizeOrString::U(v) => Ok(v),
        UsizeOrString::S(s) => s.parse::<usize>().map_err(|_| Error::invalid_value(Unexpected::Str(&s), &"a number or numeric string")),
    }
}

fn de_f32_flexible<'de, D>(deserializer: D) -> Result<f32, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::{Error, Unexpected};
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum F32OrString { F(f32), I(i64), S(String) }
    match F32OrString::deserialize(deserializer)? {
        F32OrString::F(v) => Ok(v),
        F32OrString::I(i) => Ok(i as f32),
        F32OrString::S(s) => s.parse::<f32>().map_err(|_| Error::invalid_value(Unexpected::Str(&s), &"a float or numeric string")),
    }
}

pub fn project_dir() -> PathBuf {
    // Assume binary is run from repo; fallback to current exe dir
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."))
}

pub fn find_config_path_for_read() -> PathBuf {
    // 1) current working directory
    let cwd_path = env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
        .join(WTF_CONFIG_FILENAME);
    if cwd_path.exists() { return cwd_path; }

    // 2) project dir (where binary lives)
    let proj_path = project_dir().join(WTF_CONFIG_FILENAME);
    if proj_path.exists() { return proj_path; }

    // 3) XDG
    let xdg = env::var("XDG_CONFIG_HOME").map(PathBuf::from)
        .unwrap_or_else(|_| dirs::home_dir().unwrap_or_else(|| PathBuf::from("~")).join(".config"));
    let xdg_path = xdg.join("withefuck").join(WTF_CONFIG_FILENAME);
    if xdg_path.exists() { return xdg_path; }

    // 4) ~/.wtf.json
    if let Some(home) = dirs::home_dir() {
        let home_path = home.join(format!(".{}", WTF_CONFIG_FILENAME));
        if home_path.exists() { return home_path; }
    }

    // default to project dir
    proj_path
}

pub fn load_config_from(path: &Path) -> Result<Config, String> {
    let data = fs::read_to_string(path).map_err(|e| format!("Error reading config file: {e}"))?;
    serde_json::from_str::<Config>(&data)
        .map_err(|e| format!("Invalid wtf.json format: {e}"))
}

pub fn load_config() -> Result<Config, String> {
    let path = find_config_path_for_read();
    if !path.exists() {
        return Err("Config file not found. Please run 'wtf --config' first.".into());
    }
    load_config_from(&path)
}

pub fn interactive_config() -> Result<(), String> {
    let config_path = project_dir().join(WTF_CONFIG_FILENAME);
    let mut existing: Config = fs::read_to_string(&config_path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    // Show different message depending on whether a config file exists
    if config_path.exists() {
        println!("Existing configuration found. Press Enter to keep current values.");
    } else {
        println!("No existing configuration found. Please enter values.");
    }

    // If there's no existing value for required fields, force user to enter non-empty values.
    existing.api_key = Some(prompt("API Key", existing.api_key, true));
    existing.api_endpoint = Some(prompt(
        "API Endpoint (e.g. https://api.openai.com/v1/chat/completions)",
        existing.api_endpoint,
        true,
    ));
    existing.model = Some(prompt("Model name (e.g. gpt-4)", existing.model, true));
    let hc_str = prompt("Number of previous commands to include in context (less than 100)", Some(existing.history_count.to_string()), false);
    existing.history_count = hc_str.parse().ok().filter(|v| *v>0 && *v<=100).unwrap_or(3);
    let t_str = prompt("Sampling temperature for LLM (0.0-1.0)", Some(existing.temperature.to_string()), false);
    existing.temperature = t_str.parse().ok().filter(|v: &f32| *v>=0.0 && *v<=1.0).unwrap_or(0.0);

    let json = serde_json::to_string_pretty(&existing).map_err(|e| e.to_string())?;
    fs::write(&config_path, json).map_err(|e| format!("Error saving configuration: {e}"))?;
    println!("Configuration saved to {}", config_path.display());
    Ok(())
}

fn prompt(label: &str, current: Option<String>, required: bool) -> String {
    let mut stdout = io::stdout();
    let current_disp = current.clone().unwrap_or_default();
    loop {
        if current_disp.is_empty() {
            print!("{}: ", label);
        } else {
            print!("{} [{}]: ", label, current_disp);
        }
        stdout.flush().ok();

        let mut line = String::new();
        io::stdin().read_line(&mut line).ok();
        let v = line.trim();
        if v.is_empty() {
            if !current_disp.is_empty() {
                return current_disp.clone();
            }
            if required {
                println!("{} cannot be empty.", label);
                continue;
            }
            return String::new();
        } else {
            return v.to_string();
        }
    }
}
