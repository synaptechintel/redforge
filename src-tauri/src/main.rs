// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod sidecar;

use std::sync::Arc;

use tauri::{AppHandle, Manager};

use crate::sidecar::{SidecarManager, SidecarStatus};

#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You are using RedForge.", name)
}

/// Returns the current health status of the Python sidecar.
#[tauri::command]
async fn get_sidecar_status(
    app: AppHandle,
    state: tauri::State<'_, Arc<SidecarManager>>,
) -> Result<SidecarStatus, String> {
    // If we haven't started it yet, try now (lazy start)
    if let Err(e) = state.start(&app) {
        return Ok(SidecarStatus {
            connected: false,
            port: state.port(),
            version: None,
            error: Some(e),
        });
    }

    Ok(state.check_health().await)
}

/// Force a restart of the sidecar (useful for development).
#[tauri::command]
async fn restart_sidecar(
    app: AppHandle,
    state: tauri::State<'_, Arc<SidecarManager>>,
) -> Result<SidecarStatus, String> {
    state.stop();
    state.start(&app)?;
    Ok(state.check_health().await)
}

/// Return useful paths for the Settings view (data dir, log file, etc).
#[tauri::command]
fn get_app_paths(app: AppHandle) -> Result<serde_json::Value, String> {
    let app_data = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("app_data_dir: {}", e))?;
    let log_file = app_data.join("logs").join("sidecar.log");
    let db_file = app_data.join("redforge.db");
    Ok(serde_json::json!({
        "data_dir": app_data.to_string_lossy(),
        "log_file": log_file.to_string_lossy(),
        "db_file": db_file.to_string_lossy(),
    }))
}

/// Open a path with the OS default handler (explorer.exe on Windows,
/// Finder on macOS, xdg-open on Linux). Only used for known-safe app paths.
#[tauri::command]
fn open_path(path: String) -> Result<(), String> {
    let p = std::path::PathBuf::from(&path);
    // Only allow paths under the app's data dir or its parent. Cheap guard.
    if !p.exists() {
        return Err(format!("Path does not exist: {}", path));
    }
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer.exe")
            .arg(&p)
            .spawn()
            .map_err(|e| format!("explorer: {}", e))?;
    }
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(&p)
            .spawn()
            .map_err(|e| format!("open: {}", e))?;
    }
    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(&p)
            .spawn()
            .map_err(|e| format!("xdg-open: {}", e))?;
    }
    Ok(())
}

fn main() {
    let sidecar_manager = Arc::new(SidecarManager::new());

    tauri::Builder::default()
        // Single-instance: if a second RedForge.exe is launched, focus the
        // existing window instead of spawning a duplicate app + sidecar.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.unminimize();
                let _ = w.set_focus();
                let _ = w.show();
            }
        }))
        .plugin(tauri_plugin_shell::init())
        // Updater: checks GitHub Releases latest.json. User-initiated only
        // (not auto-applied) - see the Settings view "Check for updates" button.
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .manage(sidecar_manager.clone())
        .invoke_handler(tauri::generate_handler![
            greet,
            get_sidecar_status,
            restart_sidecar,
            get_app_paths,
            open_path
        ])
        .setup(move |app| {
            let app_handle = app.handle().clone();
            let manager = sidecar_manager.clone();

            // Attempt to start the sidecar early (non-blocking)
            tauri::async_runtime::spawn(async move {
                // Small delay so the window can appear first
                tokio::time::sleep(std::time::Duration::from_millis(400)).await;

                if let Err(e) = manager.start(&app_handle) {
                    eprintln!("[RedForge] Sidecar auto-start failed: {}", e);
                }
            });

            // Clean shutdown when the last window closes
            let manager_for_exit = sidecar_manager.clone();
            if let Some(main_window) = app.get_webview_window("main") {
                main_window.on_window_event(move |event| {
                    if let tauri::WindowEvent::CloseRequested { .. } = event {
                        manager_for_exit.stop();
                    }
                });
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
