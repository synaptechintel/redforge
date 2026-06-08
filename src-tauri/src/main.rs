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

fn main() {
    let sidecar_manager = Arc::new(SidecarManager::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(sidecar_manager.clone())
        .invoke_handler(tauri::generate_handler![
            greet,
            get_sidecar_status,
            restart_sidecar
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
