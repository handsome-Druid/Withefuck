use serde::Deserialize;
use serde_json::json;
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct LlmClient {
    pub api_key: String,
    pub api_endpoint: String,
    pub model: String,
    pub temperature: f32,
}

#[derive(Debug, Deserialize)]
struct ChatResponse {
    choices: Vec<Choice>,
}

#[derive(Debug, Deserialize)]
struct Choice { message: Message }

#[derive(Debug, Deserialize)]
struct Message { content: String }

impl LlmClient {
    pub fn new(api_key: String, api_endpoint: String, model: String, temperature: f32) -> Self {
        Self { api_key, api_endpoint, model, temperature }
    }

    pub fn suggest(&self, prompt: &str) -> Result<Option<String>, String> {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .map_err(|e| format!("Failed to build HTTP client: {e}"))?;
        let payload = json!({
            "model": self.model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": self.temperature,
        });
        let resp = client.post(&self.api_endpoint)
            .header("Content-Type", "application/json")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .json(&payload)
            .send()
            .map_err(|e| format!("API call error: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("API call failed: {}", resp.text().unwrap_or_default()));
        }
        let body: ChatResponse = resp.json().map_err(|e| format!("API response parse error: {e}"))?;
        if let Some(first) = body.choices.into_iter().next() {
            let s = first.message.content.trim().to_string();
            if s == "None" { Ok(None) } else { Ok(Some(s)) }
        } else {
            Err("API response format error: no choices".into())
        }
    }
}
