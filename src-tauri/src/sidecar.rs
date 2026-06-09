//! RedForge Python Sidecar Manager
//!
//! Responsibilities:
//! - Spawn the Python sidecar process (dev or bundled)
//! - Track its health via HTTP /health endpoint
//! - Provide clean shutdown on app exit
//!
//! Port is dynamically picked at startup. Preferred default is 18765 (for
//! easy debugging - URL bar friendly) but if it's taken, we walk upward
//! through 18766..18800 to find a free one. The selected port is exposed
//! to the frontend via get_sidecar_status() and passed to the sidecar
//! process via the REDFORGE_SIDECAR_PORT env var.

use std::net::TcpListener;
use std::process::{Child, Command};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

const PREFERRED_PORT: u16 = 18765;
const PORT_SEARCH_RANGE: u16 = 35;  // tries 18765..=18799

/// Pick the first port in [PREFERRED_PORT, PREFERRED_PORT + PORT_SEARCH_RANGE]
/// that we can actually bind to on 127.0.0.1. Falls back to 18765 if nothing
/// is bindable (caller will still get a useful error from the spawn attempt).
fn pick_free_port() -> u16 {
    for offset in 0..=PORT_SEARCH_RANGE {
        let candidate = PREFERRED_PORT + offset;
        if TcpListener::bind(("127.0.0.1", candidate)).is_ok() {
            // Listener drops here, freeing the port for the sidecar to grab.
            return candidate;
        }
    }
    PREFERRED_PORT
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SidecarStatus {
    pub connected: bool,
    pub port: u16,
    pub version: Option<String>,
    pub error: Option<String>,
}

pub struct SidecarManager {
    child: Arc<Mutex<Option<Child>>>,
    port: u16,
}

impl SidecarManager {
    pub fn new() -> Self {
        let port = pick_free_port();
        println!("[RedForge] Sidecar port allocated: {} (preferred {})", port, PREFERRED_PORT);
        Self {
            child: Arc::new(Mutex::new(None)),
            port,
        }
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    /// Attempt to start the sidecar.
    /// Production: Uses the bundled external binary declared in tauri.conf.json (externalBin).
    /// Development: Falls back to running uvicorn from the sidecar/ directory.
    pub fn start(&self, app_handle: &AppHandle) -> Result<(), String> {
        let mut child_guard = self.child.lock().unwrap();

        if child_guard.is_some() {
            return Ok(()); // already running
        }

        let resource_dir = app_handle.path().resource_dir().ok();
        // Tauri's externalBin places the sidecar binary as a SIBLING of the main exe in production.
        let exe_dir = std::env::current_exe().ok().and_then(|p| p.parent().map(|p| p.to_path_buf()));

        // Strategy 1: Production bundled sidecar (via externalBin in tauri.conf.json).
        // We try every realistic location across platforms.
        let bundled_candidates = vec![
            // Sibling of main exe - this is where Tauri externalBin actually lands in production
            exe_dir.as_ref().map(|d| d.join("redforge-sidecar.exe")),
            exe_dir.as_ref().map(|d| d.join("redforge-sidecar")),
            // Tauri resources dir
            resource_dir.as_ref().map(|d| d.join("redforge-sidecar.exe")),
            resource_dir.as_ref().map(|d| d.join("redforge-sidecar")),
            resource_dir.as_ref().map(|d| d.join("binaries/redforge-sidecar.exe")),
            resource_dir.as_ref().map(|d| d.join("binaries/redforge-sidecar")),
            resource_dir.as_ref().map(|d| d.join("binaries/redforge-sidecar-x86_64-pc-windows-msvc.exe")),
            // App data dir (some setups)
            app_handle.path().app_data_dir().ok().map(|d| d.join("redforge-sidecar.exe")),
            app_handle.path().app_data_dir().ok().map(|d| d.join("redforge-sidecar")),
        ];

        for candidate in bundled_candidates.into_iter().flatten() {
            if candidate.exists() {
                println!("[RedForge] Starting bundled production sidecar: {:?}", candidate);
                let mut cmd = Command::new(&candidate);
                cmd.env("REDFORGE_SIDECAR_PORT", self.port.to_string());

                if let Some(app_data) = app_handle.path().app_data_dir().ok() {
                    cmd.env("REDFORGE_DATA_DIR", &app_data);
                    println!("[RedForge] (bundled) REDFORGE_DATA_DIR = {:?}", app_data);
                }

                let child = cmd
                    .spawn()
                    .map_err(|e| format!("Failed to spawn bundled sidecar: {}", e))?;

                *child_guard = Some(child);
                return Ok(());
            }
        }

        // Strategy 2: Development fallback - run uvicorn directly
        // This works great on Linux/macOS dev machines.
        // On Windows dev, users should have Python + the sidecar/ folder.
        println!("[RedForge] No bundled sidecar found. Falling back to uvicorn (dev mode)...");

        // Try python3 first, then python
        let python_cmd = if cfg!(target_os = "windows") {
            "python"
        } else {
            "python3"
        };

        // The sidecar directory is expected to be at <project-root>/sidecar relative to cwd in dev.
        // Tauri dev usually runs from the project root.
        let sidecar_dir = std::env::current_dir()
            .unwrap_or_else(|_| ".".into())
            .join("sidecar");

        let mut cmd = Command::new(python_cmd);
        cmd.arg("-m")
            .arg("uvicorn")
            .arg("engine:app")
            .arg("--host")
            .arg("127.0.0.1")
            .arg("--port")
            .arg(self.port.to_string())
            .current_dir(&sidecar_dir)
            .env("REDFORGE_SIDECAR_PORT", self.port.to_string());

        // Pass proper app data directory so the sidecar knows where to put redforge.db
        if let Some(app_data) = app_handle.path().app_data_dir().ok() {
            cmd.env("REDFORGE_DATA_DIR", &app_data);
            println!("[RedForge] Passing REDFORGE_DATA_DIR = {:?}", app_data);
        }

        // On Windows we often want to see the console for logs during dev
        if cfg!(target_os = "windows") {
            // For now we keep it attached. In future we can detach + log to file.
        }

        match cmd.spawn() {
            Ok(child) => {
                println!("[RedForge] Sidecar spawned via uvicorn on port {}", self.port);
                *child_guard = Some(child);
                Ok(())
            }
            Err(e) => {
                Err(format!(
                    "Failed to start Python sidecar via {} in {:?}: {}\n\n\
                     === For Development ===\n\
                     1. cd sidecar\n\
                     2. pip install -r requirements.txt\n\
                     3. (Optional but recommended) pyinstaller redforge-sidecar.spec\n\n\
                     === For Production Builds ===\n\
                     You must build the sidecar with PyInstaller first and place the binary\n\
                     so Tauri can bundle it (see README 'Building for Release').",
                    python_cmd, sidecar_dir, e
                ))
            }
        }
    }

    pub fn stop(&self) {
        let mut child_guard = self.child.lock().unwrap();
        if let Some(mut child) = child_guard.take() {
            let _ = child.kill();
            let _ = child.wait();
            println!("[RedForge] Sidecar process terminated.");
        }
    }

    pub async fn check_health(&self) -> SidecarStatus {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_millis(800))
            .build()
            .unwrap();

        let health_url = format!("http://127.0.0.1:{}/health", self.port);
        match client.get(&health_url).send().await {
            Ok(resp) if resp.status().is_success() => {
                // Try to parse the health response
                if let Ok(json) = resp.json::<serde_json::Value>().await {
                    SidecarStatus {
                        connected: true,
                        port: self.port,
                        version: json.get("version").and_then(|v| v.as_str()).map(|s| s.to_string()),
                        error: None,
                    }
                } else {
                    SidecarStatus {
                        connected: true,
                        port: self.port,
                        version: None,
                        error: None,
                    }
                }
            }
            Ok(resp) => SidecarStatus {
                connected: false,
                port: self.port,
                version: None,
                error: Some(format!("HTTP {}", resp.status())),
            },
            Err(e) => SidecarStatus {
                connected: false,
                port: self.port,
                version: None,
                error: Some(e.to_string()),
            },
        }
    }
}

impl Drop for SidecarManager {
    fn drop(&mut self) {
        self.stop();
    }
}
