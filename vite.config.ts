import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// https://vitejs.dev/config/
export default defineConfig(async () => ({
  plugins: [react()],

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent vite from obscuring rust errors
  clearScreen: false,
  // 2. tauri expects a fixed port, fail if that port is not available
  server: {
    // Port 5173 (Vite default). We moved OFF the Tauri-convention 1420
    // because on Windows with Hyper-V/WSL/Docker, port 1420 frequently
    // lands inside a reserved port range (netsh excludedportrange),
    // causing `EACCES: permission denied ::1:1420` at dev startup.
    port: 5173,
    strictPort: true,
    // Force IPv4 loopback. Without this Vite may try to bind ::1 (IPv6),
    // which is what triggers the EACCES on reserved ranges.
    host: "127.0.0.1",
    watch: {
      // 3. tell vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
  },
}));
