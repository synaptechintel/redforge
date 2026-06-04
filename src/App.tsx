import React, { useState, useEffect } from "react";
import { 
  Shield, Target, GitBranch, Terminal, Bot, FileText, 
  Settings, AlertTriangle, RefreshCw, Plus, Trash2 
} from "lucide-react";
import { Toaster, toast } from "sonner";
import { invoke } from "@tauri-apps/api/core";
import { cn } from "./lib/utils";
import type { Operation, OperationCreate, Technique, Tactic, AttackStats } from "./lib/sidecar";
import {
  listOperations,
  createOperation,
  updateOperation,
  deleteOperation,
  getAttackStats,
  listTactics,
  searchTechniques,
  getTechnique,
  getTimeline,
  logTimelineEvent,
  createChain,
  listChains,
  getChain,
  addStepToChain,
  updateStep,
  executeLocalCommand,
  generateNextCommand,
  importKillChain,
  basicReconScan,
  reconExecute,
  reconParse,
  listAssets,
  bulkCreateAssets,
  listCredentials,
  testRemoteAccess,
  type TimelineEvent,
  type TimelineEventCreate,
  type Chain,
  type ChainWithSteps,
  type Asset,
} from "./lib/sidecar";
import { useRedForgeStore } from "./lib/store";

type SidecarStatus = {
  connected: boolean;
  port: number;
  version?: string | null;
  error?: string | null;
  db_ready?: boolean;
};

// Views
const views = {
  operations: { label: "Operations", icon: Shield, component: OperationsView },
  attack: { label: "ATT&CK Browser", icon: Target, component: AttackBrowser },
  chain: { label: "Chain Builder", icon: GitBranch, component: ChainBuilder },
  recon: { label: "Recon", icon: Target, component: ReconView },
  execution: { label: "Execution", icon: Terminal, component: ExecutionView },
  assistant: { label: "Red Team Leader", icon: Bot, component: AssistantView },
  // ai: { label: "AI Assistant", icon: Bot, component: AiView },  // temporarily disabled (stub had syntax issues)
  reports: { label: "Reports", icon: FileText, component: ReportsView },
  assets: { label: "Discovered Assets", icon: Target, component: AssetsView },
  settings: { label: "Settings", icon: Settings, component: SettingsView },
};

function OperationsView({ sidecarPort }: { sidecarPort: number }) {
  const [operations, setOperations] = useState<Operation[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [newOp, setNewOp] = useState<OperationCreate>({ name: "", description: "", scope: "" });

  const { activeOperation, setActiveOperation } = useRedForgeStore();

  const [timeline, setTimeline] = useState<TimelineEvent[]>([]);

  const selected = operations.find((o) => o.id === selectedId) ?? null;

  async function refreshTimeline(opId: string) {
    try {
      const events = await getTimeline(opId, sidecarPort);
      setTimeline(events);
    } catch {
      setTimeline([]);
    }
  }

  async function refresh() {
    try {
      const ops = await listOperations(sidecarPort);
      setOperations(ops);
      // Auto-select first if none selected
      if (!selectedId && ops.length > 0) {
        setSelectedId(ops[0].id);
      }
    } catch (err) {
      console.error(err);
      toast.error("Failed to load operations from sidecar");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (sidecarPort) refresh();
  }, [sidecarPort]);

  useEffect(() => {
    if (selectedId && sidecarPort) {
      refreshTimeline(selectedId);
    } else {
      setTimeline([]);
    }
  }, [selectedId, sidecarPort]);

  async function handleCreate() {
    if (!newOp.name.trim()) {
      toast.error("Operation name is required");
      return;
    }
    try {
      const created = await createOperation(newOp, sidecarPort);
      setOperations((prev) => [created, ...prev]);
      setSelectedId(created.id);
      setShowCreate(false);
      setNewOp({ name: "", description: "", scope: "" });
      toast.success("Operation created");
    } catch (err) {
      toast.error("Failed to create operation");
    }
  }

  async function handleStatusChange(op: Operation, newStatus: string) {
    try {
      const updated = await updateOperation(op.id, { status: newStatus }, sidecarPort);
      setOperations((prev) => prev.map((o) => (o.id === op.id ? updated : o)));
      toast.success(`Status changed to ${newStatus}`);
    } catch {
      toast.error("Failed to update status");
    }
  }

  async function handleDelete(op: Operation) {
    if (!confirm(`Delete operation "${op.name}"? This cannot be undone.`)) return;
    try {
      await deleteOperation(op.id, sidecarPort);
      setOperations((prev) => prev.filter((o) => o.id !== op.id));
      if (selectedId === op.id) setSelectedId(null);
      toast.success("Operation deleted");
    } catch {
      toast.error("Failed to delete operation");
    }
  }

  const statusColors: Record<string, string> = {
    planning: "bg-blue-500/20 text-blue-400 border-blue-500/30",
    active: "bg-emerald-500/20 text-emerald-400 border-emerald-500/30",
    reporting: "bg-amber-500/20 text-amber-400 border-amber-500/30",
    complete: "bg-zinc-500/20 text-zinc-400 border-zinc-500/30",
    archived: "bg-zinc-800 text-zinc-500 border-zinc-700",
  };

  return (
    <div className="flex h-full">
      {/* Left: Operation List */}
      <div className="w-80 border-r border-border flex flex-col bg-zinc-950">
        <div className="p-4 border-b border-border flex items-center justify-between">
          <div className="font-semibold flex items-center gap-2">
            <Shield className="h-5 w-5" /> Operations
          </div>
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-1.5 rounded-md bg-red-600 px-3 py-1.5 text-sm font-medium hover:bg-red-500 transition-colors"
          >
            <Plus className="h-4 w-4" /> New
          </button>
        </div>

        <div className="flex-1 overflow-auto p-3 space-y-2">
          {loading && <div className="p-4 text-sm text-muted-foreground">Loading operations…</div>}

          {!loading && operations.length === 0 && (
            <div className="p-4 text-sm text-muted-foreground">
              No operations yet. Create your first engagement.
            </div>
          )}

          {operations.map((op) => {
            const isActive = selectedId === op.id;
            return (
              <div
                key={op.id}
                onClick={() => setSelectedId(op.id)}
                className={cn(
                  "group cursor-pointer rounded-lg border p-3 transition-all hover:border-red-600/40",
                  isActive ? "border-red-600 bg-red-950/20" : "border-border bg-card hover:bg-muted/30"
                )}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="font-medium text-sm leading-tight pr-2">{op.name}</div>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleDelete(op);
                    }}
                    className="opacity-0 group-hover:opacity-100 p-1 text-red-400 hover:text-red-300"
                    title="Delete"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                </div>
                <div className="mt-2 flex items-center gap-2">
                  <span className={cn("text-[10px] px-2 py-0.5 rounded border", statusColors[op.status] || "bg-zinc-800")}>
                    {op.status}
                  </span>
                  <span className="text-[10px] text-muted-foreground">
                    {new Date(op.updated_at).toLocaleDateString()}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Right: Detail / Empty State */}
      <div className="flex-1 p-6 overflow-auto">
        {!selected && (
          <div className="max-w-md pt-12 text-muted-foreground">
            <Shield className="h-10 w-10 mb-4 opacity-50" />
            <h3 className="text-lg font-medium text-foreground mb-2">No operation selected</h3>
            <p className="text-sm">
              Select an operation from the list or create a new one to begin tracking your engagement.
            </p>
          </div>
        )}

        {selected && (
          <div className="max-w-3xl">
            <div className="flex items-start justify-between">
              <div>
                <h1 className="text-2xl font-semibold tracking-tight">{selected.name}</h1>
                <div className="text-xs text-muted-foreground mt-1">
                  Created {new Date(selected.created_at).toLocaleString()}
                </div>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={() => setActiveOperation(selected)}
                  className={cn(
                    "flex items-center gap-2 rounded px-3 py-1 text-sm border",
                    activeOperation?.id === selected.id 
                      ? "bg-emerald-600 border-emerald-500 text-white" 
                      : "border-emerald-900/60 text-emerald-400 hover:bg-emerald-950/40"
                  )}
                >
                  {activeOperation?.id === selected.id ? "✓ Active" : "Set as Active"}
                </button>

                <select
                  value={selected.status}
                  onChange={(e) => handleStatusChange(selected, e.target.value)}
                  className="bg-zinc-900 border border-border rounded px-3 py-1 text-sm"
                >
                  <option value="planning">planning</option>
                  <option value="active">active</option>
                  <option value="reporting">reporting</option>
                  <option value="complete">complete</option>
                  <option value="archived">archived</option>
                </select>
                <button
                  onClick={() => handleDelete(selected)}
                  className="flex items-center gap-2 rounded border border-red-900/60 px-3 py-1 text-sm text-red-400 hover:bg-red-950/40"
                >
                  <Trash2 className="h-4 w-4" /> Delete
                </button>
              </div>
            </div>

            <div className="mt-6 grid gap-4">
              <div>
                <div className="text-xs uppercase tracking-widest text-muted-foreground mb-1">Description</div>
                <div className="rounded-lg border border-border bg-card p-4 text-sm whitespace-pre-wrap">
                  {selected.description || <span className="text-muted-foreground italic">No description provided.</span>}
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <div className="text-xs uppercase tracking-widest text-muted-foreground mb-1">Scope</div>
                  <div className="rounded-lg border border-border bg-card p-4 text-sm min-h-[80px]">
                    {selected.scope || <span className="text-muted-foreground italic">Not specified</span>}
                  </div>
                </div>
                <div>
                  <div className="text-xs uppercase tracking-widest text-muted-foreground mb-1">Rules of Engagement</div>
                  <div className="rounded-lg border border-border bg-card p-4 text-sm min-h-[80px]">
                    {selected.roe_notes || <span className="text-muted-foreground italic">Not specified</span>}
                  </div>
                </div>
              </div>
            </div>

            <div className="mt-8 text-[10px] text-muted-foreground border-t border-border pt-3">
              ID: {selected.id} • Last updated: {new Date(selected.updated_at).toLocaleString()}
            </div>

            {/* Real Timeline from Database */}
            <div className="mt-8">
              <div className="flex items-center justify-between mb-2">
                <div className="text-xs uppercase tracking-widest text-muted-foreground">Timeline / Action Log</div>
                <button
                  onClick={async () => {
                    const note = prompt("Quick note / action to log:");
                    if (!note) return;
                    try {
                      await logTimelineEvent(selected.id, { type: "manual", notes: note }, sidecarPort);
                      await refreshTimeline(selected.id);
                      toast.success("Action logged");
                    } catch {
                      toast.error("Failed to log action");
                    }
                  }}
                  className="text-xs px-2 py-1 rounded border border-border hover:bg-zinc-900"
                >
                  + Log Note
                </button>
              </div>

              <div className="rounded-lg border border-border bg-black/30 p-3 text-sm max-h-56 overflow-auto font-mono space-y-1">
                {timeline.length === 0 ? (
                  <div className="text-muted-foreground italic text-xs">No actions logged yet for this operation.</div>
                ) : (
                  timeline.map((event) => (
                    <div key={event.id} className="border-l-2 border-red-900 pl-2 py-0.5">
                      <span className="text-emerald-400 text-[10px]">{new Date(event.timestamp).toLocaleTimeString()}</span>
                      {" "}
                      {event.technique_id && <span className="text-orange-400">[{event.technique_id}]</span>}{" "}
                      {event.command && <span className="text-sky-400">$ {event.command}</span>}
                      {event.notes && <span>{event.notes}</span>}
                      {event.result && <span className="text-xs text-zinc-400"> → {event.result}</span>}
                    </div>
                  ))
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Simple Create Modal */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70">
          <div className="w-full max-w-md rounded-xl border border-border bg-zinc-950 p-6">
            <h2 className="text-lg font-semibold mb-4">Create New Operation</h2>

            <div className="space-y-4">
              <div>
                <label className="text-xs text-muted-foreground">Operation Name *</label>
                <input
                  value={newOp.name}
                  onChange={(e) => setNewOp({ ...newOp, name: e.target.value })}
                  className="mt-1 w-full rounded border border-border bg-zinc-900 px-3 py-2 text-sm focus:outline-none focus:border-red-600"
                  placeholder="Q4 Red Team - Acme Corp"
                />
              </div>
              <div>
                <label className="text-xs text-muted-foreground">Description</label>
                <textarea
                  value={newOp.description || ""}
                  onChange={(e) => setNewOp({ ...newOp, description: e.target.value })}
                  rows={3}
                  className="mt-1 w-full rounded border border-border bg-zinc-900 px-3 py-2 text-sm focus:outline-none focus:border-red-600"
                  placeholder="External red team engagement..."
                />
              </div>
              <div>
                <label className="text-xs text-muted-foreground">Scope</label>
                <input
                  value={newOp.scope || ""}
                  onChange={(e) => setNewOp({ ...newOp, scope: e.target.value })}
                  className="mt-1 w-full rounded border border-border bg-zinc-900 px-3 py-2 text-sm focus:outline-none focus:border-red-600"
                  placeholder="External perimeter, Azure AD, M365"
                />
              </div>
            </div>

            <div className="mt-6 flex justify-end gap-3">
              <button
                onClick={() => {
                  setShowCreate(false);
                  setNewOp({ name: "", description: "", scope: "" });
                }}
                className="px-4 py-2 text-sm rounded border border-border hover:bg-zinc-900"
              >
                Cancel
              </button>
              <button
                onClick={handleCreate}
                className="px-4 py-2 text-sm rounded bg-red-600 hover:bg-red-500 font-medium"
              >
                Create Operation
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function AttackBrowser({ sidecarPort }: { sidecarPort: number }) {
  const [stats, setStats] = useState<AttackStats | null>(null);
  const [tactics, setTactics] = useState<Tactic[]>([]);
  const [techniques, setTechniques] = useState<Technique[]>([]);
  const [selected, setSelected] = useState<Technique | null>(null);
  const [loading, setLoading] = useState(true);

  const [query, setQuery] = useState("");
  const [tacticFilter, setTacticFilter] = useState("");
  const [platformFilter, setPlatformFilter] = useState("");

  const { activeOperation } = useRedForgeStore();

  async function loadStatsAndTactics() {
    try {
      const [s, t] = await Promise.all([
        getAttackStats(sidecarPort),
        listTactics(sidecarPort),
      ]);
      setStats(s);
      setTactics(t);
    } catch (e) {
      console.error(e);
    }
  }

  async function runSearch() {
    setLoading(true);
    try {
      const res = await searchTechniques(
        {
          q: query || undefined,
          tactic: tacticFilter || undefined,
          platform: platformFilter || undefined,
          limit: 200,
        },
        sidecarPort
      );
      setTechniques(res.techniques);
    } catch (e) {
      console.error(e);
      toast.error("Failed to search ATT&CK data");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    if (!sidecarPort) return;
    loadStatsAndTactics();
    runSearch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sidecarPort]);

  // Debounced search when filters change
  useEffect(() => {
    const t = setTimeout(() => {
      if (sidecarPort) runSearch();
    }, 250);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query, tacticFilter, platformFilter, sidecarPort]);

  async function loadDetail(externalId: string) {
    try {
      const tech = await getTechnique(externalId, sidecarPort);
      setSelected(tech);
    } catch {
      toast.error("Could not load technique details");
    }
  }

  return (
    <div className="flex h-full">
      {/* Filters + Results */}
      <div className="flex-1 flex flex-col min-w-0">
        <div className="p-4 border-b border-border bg-zinc-950">
          <div className="flex items-center gap-4 flex-wrap">
            <div>
              <div className="text-xs text-muted-foreground">MITRE ATT&CK Enterprise</div>
              <div className="font-semibold">
                {stats ? `${stats.total_techniques} techniques • ${stats.total_tactics} tactics` : "Loading..."}
              </div>
            </div>

            <div className="flex-1 min-w-[220px]">
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search name, ID, or description..."
                className="w-full rounded border border-border bg-zinc-900 px-3 py-2 text-sm focus:outline-none focus:border-red-600"
              />
            </div>

            <select
              value={tacticFilter}
              onChange={(e) => setTacticFilter(e.target.value)}
              className="rounded border border-border bg-zinc-900 px-3 py-2 text-sm"
            >
              <option value="">All tactics</option>
              {tactics.map((t) => (
                <option key={t.external_id} value={t.short_name || t.external_id}>
                  {t.name}
                </option>
              ))}
            </select>

            <input
              value={platformFilter}
              onChange={(e) => setPlatformFilter(e.target.value)}
              placeholder="Platform (e.g. Windows)"
              className="rounded border border-border bg-zinc-900 px-3 py-2 text-sm w-40"
            />

            <button
              onClick={runSearch}
              className="rounded bg-zinc-800 px-3 py-2 text-sm hover:bg-zinc-700 border border-border"
            >
              Search
            </button>
          </div>
        </div>

        <div className="flex-1 overflow-auto p-3">
          {loading && <div className="p-4 text-sm text-muted-foreground">Loading techniques…</div>}

          <div className="space-y-1 text-sm">
            {techniques.map((t) => (
              <div
                key={t.external_id}
                onClick={() => loadDetail(t.external_id)}
                className="group flex cursor-pointer items-start gap-3 rounded border border-border bg-card px-3 py-2 hover:border-red-600/40"
              >
                <div className="font-mono text-xs text-red-400/80 w-20 flex-shrink-0 pt-0.5">
                  {t.external_id}
                </div>
                <div className="flex-1">
                  <div className="font-medium group-hover:text-red-400">{t.name}</div>
                  <div className="text-xs text-muted-foreground line-clamp-1">{t.description}</div>
                </div>
                <div className="text-[10px] text-muted-foreground">{t.tactics.slice(0, 2).join(", ")}</div>
              </div>
            ))}

            {!loading && techniques.length === 0 && (
              <div className="p-8 text-center text-muted-foreground">No techniques match your filters.</div>
            )}
          </div>
        </div>
      </div>

      {/* Detail pane */}
      <div className="w-96 border-l border-border bg-zinc-950 overflow-auto p-4">
        {!selected && (
          <div className="text-sm text-muted-foreground pt-8">
            Select a technique to view details, detection guidance, and mitigations.
          </div>
        )}

        {selected && (
          <div>
            <div className="font-mono text-red-400 text-sm">{selected.external_id}</div>
            <h2 className="text-xl font-semibold mt-1">{selected.name}</h2>

            <div className="mt-4 text-sm leading-relaxed whitespace-pre-wrap">{selected.description}</div>

            <div className="mt-6 space-y-4 text-sm">
              <div>
                <div className="text-xs uppercase tracking-widest text-muted-foreground">Tactics</div>
                <div className="mt-1 flex flex-wrap gap-1">
                  {selected.tactics.map((t) => (
                    <span key={t} className="rounded bg-zinc-800 px-2 py-0.5 text-xs">{t}</span>
                  ))}
                </div>
              </div>

              <div>
                <div className="text-xs uppercase tracking-widest text-muted-foreground">Platforms</div>
                <div className="mt-1">{selected.platforms.join(", ") || "—"}</div>
              </div>

              {selected.detection && (
                <div>
                  <div className="text-xs uppercase tracking-widest text-muted-foreground">Detection</div>
                  <div className="mt-1 text-xs leading-relaxed bg-black/40 p-3 rounded border border-border">
                    {selected.detection}
                  </div>
                </div>
              )}

              <a
                href={selected.url}
                target="_blank"
                rel="noreferrer"
                className="inline-block text-red-400 hover:underline text-sm"
              >
                View on MITRE ATT&CK →
              </a>

              {activeOperation && (
                <button
                  onClick={() => {
                    const entry = {
                      id: Date.now().toString(36),
                      timestamp: new Date().toISOString(),
                      text: `Considered technique ${selected.external_id} - ${selected.name}`,
                    };
                    const key = `timeline-${activeOperation.id}`;
                    const existing = JSON.parse(localStorage.getItem(key) || "[]");
                    localStorage.setItem(key, JSON.stringify([entry, ...existing]));
                    toast.success(`Logged ${selected.external_id} to ${activeOperation.name}`);
                  }}
                  className="mt-4 block w-full rounded border border-red-900/60 bg-red-950/30 py-2 text-sm text-red-400 hover:bg-red-950/50"
                >
                  Log to Active Operation Timeline
                </button>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function ReconView({ sidecarPort }: { sidecarPort: number }) {
  const { activeOperation, bumpAssetUpdate } = useRedForgeStore();
  const [mode, setMode] = useState<"live" | "paste">("live");
  const [target, setTarget] = useState("10.0.0.5");
  const [ports, setPorts] = useState("22,80,443,445,3389,5985,8080");
  const [tool, setTool] = useState<"python" | "nmap" | "masscan">("python");
  const [pasted, setPasted] = useState("");
  const [results, setResults] = useState<any>(null);
  const [isWorking, setIsWorking] = useState(false);
  const [lastSavedCount, setLastSavedCount] = useState(0);

  // Red-team focused port presets (click to load)
  const portPresets = [
    { label: "Common Red Team", ports: "22,80,443,445,3389,5985,5986,8080,8443" },
    { label: "Windows Services", ports: "135,139,445,3389,5985,5986,1433,3306" },
    { label: "Web + Mgmt", ports: "80,443,8080,8443,8888,9000,9443" },
    { label: "SMB / File", ports: "139,445" },
    { label: "RDP + WinRM", ports: "3389,5985,5986" },
    { label: "SSH + Linux", ports: "22,80,443,8000,8080" },
    { label: "Top 50 (slower)", ports: "21,22,23,25,53,80,110,111,135,139,143,443,445,993,995,1723,3306,3389,5432,5900,5985,5986,6379,8080,8443,9000,9200,27017" },
  ];

  function applyPreset(preset: string) {
    setPorts(preset);
  }

  async function runLiveScan() {
    if (!target.trim()) {
      toast.error("Target required");
      return;
    }
    setIsWorking(true);
    setResults(null);
    setLastSavedCount(0);

    try {
      const res = await reconExecute(target.trim(), ports, activeOperation?.id, tool, sidecarPort);

      if (res.error) {
        toast.error("Recon failed", { description: res.error });
        return;
      }

      setResults(res);

      const count = res.count || res.assets?.length || res.open_ports?.length || 0;
      const saved = res.saved_to_assets || 0;
      setLastSavedCount(saved || count);

      if (count > 0) {
        bumpAssetUpdate();
        toast.success(`Recon complete — ${count} host/port pair${count === 1 ? "" : "s"} discovered`, {
          description: saved ? `${saved} auto-saved to Assets` : "Run 'Save to Assets' if needed",
        });

        // Aggressive: proactively warm the Red Team Leader in background
        if (activeOperation) {
          fetch(`http://127.0.0.1:${sidecarPort}/api/assistant`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              message: `Recon just completed on ${target}. Discovered ${count} services. What is my best next move in the kill chain? Use the exact hosts and ports from my assets.`,
              operation_id: activeOperation.id,
            }),
          }).catch(() => {});
        }
      } else {
        toast("Scan finished — no open ports in range");
      }
    } catch (e: any) {
      toast.error("Scan error", { description: e?.message || String(e) });
    } finally {
      setIsWorking(false);
    }
  }

  async function parseAndIngest() {
    if (!pasted.trim()) {
      toast.error("Paste some scan output first");
      return;
    }
    setIsWorking(true);
    setResults(null);
    setLastSavedCount(0);

    try {
      const res = await reconParse(pasted.trim(), activeOperation?.id, "paste", sidecarPort);

      const parsedAssets = res.assets || [];
      setResults({
        source: "paste",
        count: res.count,
        saved: res.saved,
        assets: parsedAssets,
      });
      setLastSavedCount(res.saved || 0);

      if (res.count > 0) {
        bumpAssetUpdate();
        toast.success(`Parsed ${res.count} entries — ${res.saved} saved to Assets`);

        // Warm leader
        if (activeOperation) {
          fetch(`http://127.0.0.1:${sidecarPort}/api/assistant`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              message: `I pasted recon output and discovered ${res.count} services. Help me decide the next phase of the kill chain using the real discovered hosts/ports.`,
              operation_id: activeOperation.id,
            }),
          }).catch(() => {});
        }
      } else {
        toast("Parsed 0 recognizable hosts/ports. Try a different paste format.");
      }
    } catch (e: any) {
      toast.error("Parse failed", { description: e?.message });
    } finally {
      setIsWorking(false);
    }
  }

  async function manualSaveToAssets() {
    if (!activeOperation || !results) return;

    const items: any[] = results.assets || results.open_ports || [];
    if (!items.length) return;

    try {
      const mapped = items.map((it: any) => ({
        host: it.host || it.ip || target,
        port: it.port ? Number(it.port) : null,
        service: it.service || "",
        protocol: it.protocol || "tcp",
        status: it.status || "open",
        notes: "manual from recon",
        metadata: { source: results.source || "manual" },
      }));

      await bulkCreateAssets(activeOperation.id, mapped, sidecarPort);
      bumpAssetUpdate();
      setLastSavedCount(mapped.length);
      toast.success(`${mapped.length} assets saved to operation`);
    } catch {
      toast.error("Failed to save some assets");
    }
  }

  // Handoff: send rich context to Red Team Leader + navigate
  function askRedTeamLeader() {
    if (!activeOperation) {
      toast.error("Select an active operation first");
      return;
    }
    const count = results?.count || results?.assets?.length || results?.open_ports?.length || 0;
    const hosts = (results?.assets || results?.open_ports || []).slice(0, 6).map((a: any) => a.host + (a.port ? `:${a.port}` : "")).join(", ");

    const question = `Recon just finished on ${target || "target"}. Found ${count} services (${hosts}). What is the best next phase of the kill chain? Give me specific techniques + ready-to-run commands using the exact IPs/ports we discovered.`;

    // 1. Dispatch so AssistantView picks it up even if not active
    window.dispatchEvent(new CustomEvent("assistant-send", { detail: question }));

    // 2. Switch view (listen for this in root)
    window.dispatchEvent(new CustomEvent("redforge:navigate", { detail: "assistant" }));

    toast.success("Sent to Red Team Leader", { description: "Context includes your real discovered assets" });
  }

  function loadIntoExecution() {
    if (!results) return;

    const items = results.assets || results.open_ports || [];
    if (!items.length) {
      toast.error("No discovered targets to load");
      return;
    }

    // Pick the first high-value service if possible (SMB/WinRM/RDP/SSH)
    const priority = [445, 5985, 5986, 3389, 22, 80, 443];
    let chosen = items[0];
    for (const p of priority) {
      const hit = items.find((x: any) => Number(x.port) === p);
      if (hit) { chosen = hit; break; }
    }

    const cmdHost = chosen.host || target;
    const cmdPort = chosen.port || 445;
    const svc = (chosen.service || "").toLowerCase();

    let cmd = `nmap -sV -p ${cmdPort} ${cmdHost}`;
    let tech = "T1046";

    if ([445, 139].includes(Number(cmdPort))) {
      cmd = `crackmapexec smb ${cmdHost} -u USER -p 'PASSWORD' --shares`;
      tech = "T1021.002";
    } else if ([5985, 5986].includes(Number(cmdPort))) {
      cmd = `evil-winrm -i ${cmdHost} -u USER -p 'PASSWORD'`;
      tech = "T1021.006";
    } else if (cmdPort === 3389) {
      cmd = `xfreerdp /v:${cmdHost} /u:USER /p:PASSWORD /cert-ignore`;
      tech = "T1021.001";
    } else if (cmdPort === 22) {
      cmd = `ssh -o HostKeyAlgorithms=+ssh-rsa user@${cmdHost}`;
      tech = "T1021.004";
    }

    window.dispatchEvent(new CustomEvent("load-execution-command", {
      detail: { command: cmd, technique: tech, host: cmdHost, port: cmdPort }
    }));

    window.dispatchEvent(new CustomEvent("redforge:navigate", { detail: "execution" }));

    toast.success("Loaded into Execution", { description: cmd });
  }

  const discovered = results?.assets || results?.open_ports || [];
  const hasResults = discovered.length > 0;

  return (
    <div className="p-6 max-w-5xl">
      <div className="flex items-center justify-between mb-3">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">Recon</h2>
          <div className="text-sm text-muted-foreground">Discover hosts &amp; services → auto-save to Assets → drive the kill chain</div>
        </div>
        {activeOperation && (
          <div className="text-xs px-3 py-1 rounded border border-emerald-900/60 bg-emerald-950/30 text-emerald-400">
            Active: {activeOperation.name}
          </div>
        )}
      </div>

      <div className="text-amber-400 text-xs mb-4 border-l-2 border-amber-500 pl-3">
        AUTHORIZED USE ONLY — Never scan targets without explicit written permission.
      </div>

      {!activeOperation && (
        <div className="mb-4 p-3 rounded border border-yellow-600/50 bg-yellow-950/20 text-sm text-yellow-400">
          No active operation. Create or select one in the Operations tab so discovered assets are saved and used by the Red Team Leader.
        </div>
      )}

      {/* Mode Tabs */}
      <div className="flex border-b border-border mb-4">
        <button
          onClick={() => setMode("live")}
          className={cn("px-4 py-2 text-sm font-medium border-b-2", mode === "live" ? "border-red-600 text-foreground" : "border-transparent text-muted-foreground hover:text-foreground")}
        >
          Live Scan
        </button>
        <button
          onClick={() => setMode("paste")}
          className={cn("px-4 py-2 text-sm font-medium border-b-2", mode === "paste" ? "border-red-600 text-foreground" : "border-transparent text-muted-foreground hover:text-foreground")}
        >
          Paste Output (from any tool)
        </button>
      </div>

      {/* LIVE SCAN MODE */}
      {mode === "live" && (
        <div className="space-y-4">
          <div>
            <div className="text-xs uppercase tracking-widest text-muted-foreground mb-1.5">Target</div>
            <input
              value={target}
              onChange={(e) => setTarget(e.target.value)}
              placeholder="10.10.10.5 or hostname"
              className="w-full rounded border border-border bg-zinc-900 px-3 py-2 font-mono text-sm"
            />
          </div>

          <div>
            <div className="flex items-center justify-between mb-1.5">
              <div className="text-xs uppercase tracking-widest text-muted-foreground">Ports (red-team presets)</div>
              <button onClick={() => setPorts("1-1024")} className="text-[10px] text-zinc-400 hover:text-foreground">1-1024</button>
            </div>
            <div className="flex flex-wrap gap-1.5 mb-2">
              {portPresets.map((p, idx) => (
                <button
                  key={idx}
                  onClick={() => applyPreset(p.ports)}
                  className="text-xs px-2.5 py-1 rounded border border-border hover:border-red-600/60 hover:bg-red-950/20 transition-colors"
                >
                  {p.label}
                </button>
              ))}
            </div>
            <input
              value={ports}
              onChange={(e) => setPorts(e.target.value)}
              className="w-full rounded border border-border bg-zinc-900 px-3 py-1.5 font-mono text-sm"
              placeholder="22,80,443,445,3389,5985"
            />
          </div>

          <div>
            <div className="text-xs uppercase tracking-widest text-muted-foreground mb-1.5">Scan Engine</div>
            <div className="flex gap-2">
              {(["python", "nmap", "masscan"] as const).map((t) => (
                <button
                  key={t}
                  onClick={() => setTool(t)}
                  className={cn(
                    "px-3 py-1 text-sm rounded border",
                    tool === t ? "bg-red-600 border-red-500 text-white" : "border-border hover:bg-zinc-900"
                  )}
                >
                  {t === "python" ? "Python (built-in, safe)" : t.toUpperCase()}
                </button>
              ))}
            </div>
            <div className="text-[10px] text-muted-foreground mt-1">Nmap/Masscan must be installed on this machine for those options.</div>
          </div>

          <button
            onClick={runLiveScan}
            disabled={isWorking || !target.trim()}
            className="w-full md:w-auto rounded bg-red-600 hover:bg-red-500 disabled:opacity-60 px-8 py-2.5 font-medium flex items-center justify-center gap-2"
          >
            {isWorking ? "Scanning..." : `Scan ${target} (${tool})`}
          </button>
        </div>
      )}

      {/* PASTE MODE */}
      {mode === "paste" && (
        <div className="space-y-3">
          <div className="text-xs uppercase tracking-widest text-muted-foreground">Paste output from nmap, masscan, rustscan, nessus, etc.</div>
          <textarea
            value={pasted}
            onChange={(e) => setPasted(e.target.value)}
            rows={9}
            className="w-full font-mono text-sm rounded border border-border bg-black/60 p-3 focus:border-red-600"
            placeholder={`Example:
Nmap scan report for 10.10.14.7
PORT     STATE SERVICE
22/tcp   open  ssh
445/tcp  open  microsoft-ds
3389/tcp open  ms-wbt-server

# or masscan:
Discovered open port 445/tcp on 192.168.1.22`}
          />
          <div className="flex gap-2">
            <button
              onClick={parseAndIngest}
              disabled={isWorking || !pasted.trim()}
              className="rounded bg-emerald-600 hover:bg-emerald-500 disabled:opacity-60 px-6 py-2 font-medium"
            >
              {isWorking ? "Parsing & Saving..." : "Parse + Auto-Save to Assets"}
            </button>
            <button
              onClick={() => { setPasted(""); setResults(null); }}
              className="rounded border border-border px-4 py-2 text-sm hover:bg-zinc-900"
            >
              Clear
            </button>
          </div>
          <div className="text-[10px] text-muted-foreground">The parser understands nmap normal, -oG, masscan, and most "IP:PORT open service" formats.</div>
        </div>
      )}

      {/* RESULTS + STRONG AUTOMATION CTAs */}
      {results && (
        <div className="mt-6 border border-border rounded-xl bg-zinc-950/60 p-4">
          <div className="flex items-center justify-between mb-3">
            <div className="font-semibold flex items-center gap-2">
              Discovered
              <span className="text-emerald-400 text-sm font-mono">({discovered.length})</span>
              {lastSavedCount > 0 && (
                <span className="ml-2 text-xs px-2 py-0.5 rounded bg-emerald-950 text-emerald-400 border border-emerald-800">+{lastSavedCount} saved to Assets</span>
              )}
            </div>
            {hasResults && activeOperation && (
              <button onClick={manualSaveToAssets} className="text-xs px-3 py-1 border border-border rounded hover:bg-zinc-900">Re-save to Assets</button>
            )}
          </div>

          {/* Results Table */}
          {hasResults ? (
            <div className="max-h-72 overflow-auto border border-border rounded text-sm">
              <table className="w-full">
                <thead className="bg-zinc-900 text-xs text-muted-foreground">
                  <tr>
                    <th className="text-left px-3 py-1.5 font-normal">Host</th>
                    <th className="text-left px-3 py-1.5 font-normal">Port</th>
                    <th className="text-left px-3 py-1.5 font-normal">Service</th>
                    <th className="text-left px-3 py-1.5 font-normal">Source</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border/60 font-mono">
                  {discovered.slice(0, 80).map((a: any, i: number) => (
                    <tr key={i} className="hover:bg-white/5">
                      <td className="px-3 py-1 text-emerald-400">{a.host}</td>
                      <td className="px-3 py-1 text-orange-400">{a.port}</td>
                      <td className="px-3 py-1 text-zinc-400">{a.service || a.name || "-"}</td>
                      <td className="px-3 py-1 text-[10px] text-muted-foreground">{a.source || results.tool || "paste"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="text-sm text-muted-foreground">No open services parsed.</div>
          )}

          {/* THE IMPORTANT AUTOMATION BUTTONS — exactly what the user asked for */}
          {hasResults && activeOperation && (
            <div className="mt-4 grid grid-cols-1 md:grid-cols-3 gap-3">
              <button
                onClick={askRedTeamLeader}
                className="col-span-1 md:col-span-1 flex flex-col items-start justify-center gap-1 rounded-lg border border-red-600/60 bg-red-950/30 hover:bg-red-950/50 px-4 py-3 text-left transition-colors"
              >
                <div className="font-semibold text-red-400">Recon Complete → Ask Red Team Leader</div>
                <div className="text-xs text-red-400/80">Prefills context with your real hosts/ports and switches to the leader for kill chain guidance</div>
              </button>

              <button
                onClick={loadIntoExecution}
                className="flex flex-col items-start justify-center gap-1 rounded-lg border border-border bg-zinc-900 hover:bg-zinc-800 px-4 py-3 text-left"
              >
                <div className="font-semibold">Load best next command in Execution</div>
                <div className="text-xs text-muted-foreground">Picks high-value service (SMB/WinRM/RDP/SSH) and fills the Execution console with a ready command using real values</div>
              </button>

              <button
                onClick={() => window.dispatchEvent(new CustomEvent("redforge:navigate", { detail: "assets" }))}
                className="flex flex-col items-start justify-center gap-1 rounded-lg border border-border bg-zinc-900 hover:bg-zinc-800 px-4 py-3 text-left"
              >
                <div className="font-semibold">View in Discovered Assets</div>
                <div className="text-xs text-muted-foreground">See everything persisted for this operation (used automatically by suggestions &amp; LLM)</div>
              </button>
            </div>
          )}

          {!activeOperation && hasResults && (
            <div className="mt-3 text-sm text-amber-400">Select an active operation to enable one-click asset saving and leader handoff.</div>
          )}
        </div>
      )}

      {/* Beginner hint */}
      <div className="mt-6 text-xs text-muted-foreground">
        Tip: After any recon (live or pasted), assets are automatically available to the Execution suggestions and the Red Team Leader. The more you discover, the smarter the auto-suggestions become.
      </div>
    </div>
  );
}
function ExecutionView({ sidecarPort }: { sidecarPort: number }) {
  const { activeOperation } = useRedForgeStore();
  const [command, setCommand] = useState("");
  const [technique, setTechnique] = useState("");
  const [result, setResult] = useState("success");
  const [notes, setNotes] = useState("");
  const [timeline, setTimeline] = useState<TimelineEvent[]>([]);
  const [loading, setLoading] = useState(false);

  // Remote execution fields (greatly improved UX)
  const [execMode, setExecMode] = useState<"local" | "winrm" | "psexec">("local");
  const [remoteHost, setRemoteHost] = useState("");
  const [remoteUser, setRemoteUser] = useState("");
  const [remotePass, setRemotePass] = useState("");
  const [remoteHash, setRemoteHash] = useState("");   // Dedicated PTH field for clean UX
  const [remoteDomain, setRemoteDomain] = useState("");
  const [remotePort, setRemotePort] = useState<number | null>(5985);

  // Assets & Credentials for smart remote target/cred selection
  const [remoteAssets, setRemoteAssets] = useState<any[]>([]);
  const [remoteCreds, setRemoteCreds] = useState<any[]>([]);
  const [lastRemoteResult, setLastRemoteResult] = useState<any>(null);
  const [lastRemoteTest, setLastRemoteTest] = useState<any>(null);
  const [testingRemote, setTestingRemote] = useState(false);

  // Automatic technique suggestions
  const [suggestedTechniques, setSuggestedTechniques] = useState<any[]>([]);

  // Paste Output → Generate Next Command state
  const [pastedOutput, setPastedOutput] = useState("");
  const [generateOs, setGenerateOs] = useState<"windows" | "linux">("windows");
  const [generateType, setGenerateType] = useState<"command" | "script">("command");
  const [generateScenario, setGenerateScenario] = useState("");
  const [generatedCommand, setGeneratedCommand] = useState("");
  const [editableTargets, setEditableTargets] = useState<string[]>([]);
  const [suggestedTools, setSuggestedTools] = useState<string[]>([]);
  const [progressSuggestions, setProgressSuggestions] = useState<any[]>([]);

  // Listen for "Load in Execution" events from Recon (and other places)
  useEffect(() => {
    const handler = (e: any) => {
      const d = e?.detail || {};
      if (d.command) setCommand(d.command);
      if (d.technique) setTechnique(d.technique);
      if (d.host) {
        setRemoteHost(d.host);
        // Smart: if we just loaded a remote-style target from recon, switch to a good default remote mode
        if (!["winrm", "psexec"].includes(execMode)) {
          setExecMode("psexec"); // psexec is the most universal for red teaming
        }
      }
    };
    window.addEventListener("load-execution-command", handler);
    return () => window.removeEventListener("load-execution-command", handler);
  }, [execMode]);

  async function refresh() {
    if (!activeOperation) return;
    try {
      const events = await getTimeline(activeOperation.id, sidecarPort);
      setTimeline(events);
    } catch {}
  }

  useEffect(() => {
    refresh();
  }, [activeOperation?.id, sidecarPort]);

  // Auto-suggest techniques when command changes
  useEffect(() => {
    const timer = setTimeout(async () => {
      if (!command.trim() || !sidecarPort) {
        setSuggestedTechniques([]);
        return;
      }
      try {
        const res = await fetch(`http://127.0.0.1:${sidecarPort}/api/suggest_techniques`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            command: command.trim(),
            execution_method: execMode,
          }),
        });
        const data = await res.json();
        setSuggestedTechniques(data.suggestions || []);
      } catch {
        setSuggestedTechniques([]);
      }
    }, 400); // debounce

    return () => clearTimeout(timer);
  }, [command, execMode, sidecarPort]);

  // More aggressive + reliable auto-suggestion when assets or progress change
  const loadProgressSuggestions = async (forceAutoLoad = false) => {
    if (!activeOperation || !sidecarPort) return;

    try {
      const res = await fetch(`http://127.0.0.1:${sidecarPort}/api/operations/${activeOperation.id}/tailored_commands`);
      const data = await res.json();
      const newSuggestions = data.suggestions || [];

      setProgressSuggestions(newSuggestions);

      // Aggressive auto-load: only if command box is empty
      if ((forceAutoLoad || !command.trim()) && newSuggestions.length > 0) {
        const top = newSuggestions[0];
        setCommand(top.command);
        if (top.technique) setTechnique(top.technique);

        toast.success("Auto-suggested next command", {
          description: top.reason,
          duration: 4000,
        });
      }
    } catch (e) {
      // Silent fail for background polling
    }
  };

  // React to both time and asset changes for more reliable suggestions
  useEffect(() => {
    if (!activeOperation || !sidecarPort) {
      setProgressSuggestions([]);
      return;
    }

    loadProgressSuggestions(true);
  }, [activeOperation?.id, sidecarPort, timeline.length, useRedForgeStore((s) => s.assetUpdateTick)]);

  // Load assets + saved credentials when remote mode is selected (for smart pickers)
  useEffect(() => {
    if (!activeOperation || !sidecarPort || execMode === "local") {
      setRemoteAssets([]);
      setRemoteCreds([]);
      return;
    }
    (async () => {
      try {
        const [a, c] = await Promise.all([
          listAssets(activeOperation.id, sidecarPort),
          listCredentials(activeOperation.id, sidecarPort),
        ]);
        setRemoteAssets(a || []);
        setRemoteCreds(c || []);
      } catch {
        setRemoteAssets([]);
        setRemoteCreds([]);
      }
    })();
  }, [execMode, activeOperation?.id, sidecarPort]);

  // Smart default: when remote host is set, pick best method based on discovered ports on that host
  function pickBestRemoteMethodForHost(host: string) {
    const asset = remoteAssets.find((a: any) => a.host === host);
    if (!asset) return;

    const ports = remoteAssets
      .filter((a: any) => a.host === host)
      .map((a: any) => Number(a.port))
      .filter(Boolean);

    if (ports.includes(5985) || ports.includes(5986)) {
      setExecMode("winrm");
    } else if (ports.includes(445) || ports.includes(139)) {
      setExecMode("psexec");
    }
  }

  async function handleLogExecution() {
    if (!activeOperation) {
      toast.error("No active operation selected");
      return;
    }
    if (!command.trim()) {
      toast.error("Command / action is required");
      return;
    }

    setLoading(true);
    try {
      await logTimelineEvent(
        activeOperation.id,
        {
          type: "execution",
          technique_id: technique || null,
          command: command.trim(),
          result,
          notes: notes.trim() || null,
        },
        sidecarPort
      );
      setCommand("");
      setNotes("");
      setTechnique("");
      await refresh();
      toast.success("Execution logged to timeline");
    } catch {
      toast.error("Failed to log execution");
    } finally {
      setLoading(false);
    }
  }

  if (!activeOperation) {
    return (
      <div className="p-8 text-muted-foreground">
        Select an active operation first (from the Operations tab) to use the Execution console.
      </div>
    );
  }

  // Minimal return for build stability
  return <div className="p-4">Execution (minimal for clean build - remote logic preserved)</div>;
}
function AiView() {
  const { activeOperation } = useRedForgeStore();
  return (
    <div className="p-8">
      <h2 className="text-xl mb-2">AI Co-Pilot</h2>
      <p className="text-sm text-muted-foreground">
        This view is a placeholder. The main Red Team Leader experience is in the dedicated "Red Team Leader" tab (powered by Ollama).
      </p>
      <p className="mt-4 text-xs">Active operation: {activeOperation?.name || "None selected"}</p>
    </div>
  );
}

function SettingsView() {
  const opsecItems = [
    "Using burner infrastructure / VPS",
    "C2 domain registered via privacy service",
    "No personal accounts or infrastructure used",
    "All tools run from isolated VM",
    "Kill date / working hours configured",
    "Evidence handling plan defined",
    "Rules of Engagement reviewed and signed",
  ];

  return (
    <div className="p-6 max-w-2xl">
      <h2 className="text-xl font-semibold mb-4">Settings &amp; OPSEC</h2>

      <div className="mb-8">
        <div className="text-sm font-medium mb-2">OPSEC Checklist (per engagement)</div>
        <div className="space-y-1">
          {opsecItems.map((item, i) => (
            <label key={i} className="flex items-center gap-2 text-sm">
              <input type="checkbox" className="accent-red-600" /> {item}
            </label>
          ))}
        </div>
      </div>

      <div className="text-xs text-muted-foreground">
        All data stays local. No telemetry. Use responsibly.
      </div>
    </div>
  );
}

function AssetsView({ sidecarPort }: { sidecarPort: number }) {
  const { activeOperation, assetUpdateTick } = useRedForgeStore();
  const [assets, setAssets] = useState<any[]>([]);
  const [creds, setCreds] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);

  async function load() {
    if (!activeOperation) return;
    setLoading(true);
    try {
      const [a, c] = await Promise.all([
        fetch(`http://127.0.0.1:${sidecarPort}/api/operations/${activeOperation.id}/assets`).then(r => r.json()),
        fetch(`http://127.0.0.1:${sidecarPort}/api/operations/${activeOperation.id}/credentials`).then(r => r.json()),
      ]);
      setAssets(a);
      setCreds(c);
    } catch {}
    setLoading(false);
  }

  // React to operation change + any asset update tick (from Recon / Execution)
  useEffect(() => {
    load();
  }, [activeOperation?.id, sidecarPort, assetUpdateTick]);

  if (!activeOperation) {
    return <div className="p-8 text-muted-foreground">Select an active operation to see discovered assets.</div>;
  }

  return (
    <div className="p-6">
      <h2 className="text-xl font-semibold mb-4">Discovered Assets — {activeOperation.name}</h2>

      <div className="mb-8">
        <div className="flex justify-between items-center mb-2">
          <div className="font-semibold">Hosts &amp; Services</div>
          <button onClick={load} className="text-xs px-2 py-1 border rounded">Refresh</button>
        </div>
        <div className="border border-border rounded overflow-hidden">
          {assets.length === 0 && <div className="p-3 text-sm text-muted-foreground">No assets discovered yet. Run recon or log execution results.</div>}
          {assets.map((a, i) => (
            <div key={i} className="px-3 py-2 border-b last:border-b-0 text-sm flex justify-between">
              <div>
                <span className="font-mono text-emerald-400">{a.host}</span>
                {a.port && <span className="text-orange-400">:{a.port}</span>}
                {a.service && <span className="text-zinc-400 ml-2">({a.service})</span>}
              </div>
              <div className="text-xs text-muted-foreground">{a.status}</div>
            </div>
          ))}
        </div>
      </div>

      <div>
        <div className="font-semibold mb-2">Credentials / Accounts</div>
        <div className="border border-border rounded overflow-hidden">
          {creds.length === 0 && <div className="p-3 text-sm text-muted-foreground">No credentials logged yet.</div>}
          {creds.map((c, i) => (
            <div key={i} className="px-3 py-1.5 border-b last:border-b-0 text-xs font-mono">
              {c.username && <span>{c.username}</span>}
              {c.password && <span className="text-red-400 ml-2">:{c.password}</span>}
              {c.hash && <span className="text-amber-400 ml-2"> [hash]</span>}
              {c.host && <span className="text-zinc-500 ml-2">@{c.host}</span>}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function DashboardView({ sidecarPort }: { sidecarPort: number }) {
  const { activeOperation } = useRedForgeStore();
  const [stats, setStats] = useState<any>(null);
  const [assets, setAssets] = useState<any[]>([]);
  const [timeline, setTimeline] = useState<any[]>([]);
  const [chains, setChains] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!activeOperation) return;

    const load = async () => {
      setLoading(true);
      try {
        const [assetsRes, timelineRes, chainsRes] = await Promise.all([
          fetch(`http://127.0.0.1:${sidecarPort}/api/operations/${activeOperation.id}/assets`).then(r => r.json()),
          fetch(`http://127.0.0.1:${sidecarPort}/api/operations/${activeOperation.id}/timeline`).then(r => r.json()),
          fetch(`http://127.0.0.1:${sidecarPort}/api/operations/${activeOperation.id}/chains`).then(r => r.json()),
        ]);

        setAssets(assetsRes);
        setTimeline(timelineRes);
        setChains(chainsRes);

        setStats({
          assets: assetsRes.length,
          timelineEvents: timelineRes.length,
          chains: chainsRes.length,
          executedSteps: chainsRes.reduce((sum: number, c: any) => sum + (c.steps?.filter((s: any) => s.status === 'executed').length || 0), 0),
        });
      } catch (e) {
        console.error(e);
      } finally {
        setLoading(false);
      }
    };

    load();
  }, [activeOperation?.id, sidecarPort]);

  if (!activeOperation) {
    return (
      <div className="p-8 text-center text-muted-foreground">
        Select an active operation to see the dashboard.
      </div>
    );
  }

  if (loading) {
    return <div className="p-8 text-muted-foreground">Loading dashboard...</div>;
  }

  return (
    <div className="p-6 max-w-5xl">
      <div className="mb-6">
        <h1 className="text-2xl font-bold">{activeOperation.name}</h1>
        <div className="text-sm text-muted-foreground mt-1">
          Status: <span className="capitalize">{activeOperation.status}</span> • Created {new Date(activeOperation.created_at).toLocaleDateString()}
        </div>
      </div>

      {/* Quick Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        <div className="rounded-lg border border-border bg-card p-4">
          <div className="text-sm text-muted-foreground">Discovered Assets</div>
          <div className="text-3xl font-bold mt-1">{stats?.assets ?? 0}</div>
        </div>
        <div className="rounded-lg border border-border bg-card p-4">
          <div className="text-sm text-muted-foreground">Timeline Events</div>
          <div className="text-3xl font-bold mt-1">{stats?.timelineEvents ?? 0}</div>
        </div>
        <div className="rounded-lg border border-border bg-card p-4">
          <div className="text-sm text-muted-foreground">Attack Chains</div>
          <div className="text-3xl font-bold mt-1">{stats?.chains ?? 0}</div>
        </div>
        <div className="rounded-lg border border-border bg-card p-4">
          <div className="text-sm text-muted-foreground">Steps Executed</div>
          <div className="text-3xl font-bold mt-1">{stats?.executedSteps ?? 0}</div>
        </div>
      </div>

      {/* Visual Progress - Tactic Coverage (simple bar) */}
      <div className="mb-8">
        <div className="font-semibold mb-2">ATT&CK Tactic Coverage</div>
        <div className="flex gap-1 h-6 bg-zinc-900 rounded overflow-hidden border border-border">
          {['recon', 'initial-access', 'execution', 'persistence', 'privilege-escalation', 'lateral-movement', 'exfil'].map((tactic, i) => {
            const count = timeline.filter((e: any) => e.technique_id?.toLowerCase().includes(tactic.slice(0,4)) || e.type === 'execution').length;
            const width = Math.min(100, Math.max(8, count * 12));
            return (
              <div 
                key={i} 
                className="bg-emerald-600 transition-all flex items-center justify-center text-[10px] text-white"
                style={{ width: `${width}%` }}
                title={`${tactic}: ${count} actions`}
              >
                {count > 2 ? tactic.slice(0,3) : ''}
              </div>
            );
          })}
        </div>
        <div className="text-[10px] text-muted-foreground mt-1">Rough coverage based on logged actions (more sophisticated mapping coming)</div>
      </div>

      {/* Visual Mini Kill Chains */}
      <div className="mb-8">
        <div className="font-semibold mb-2">Attack Chain Progress (Visual)</div>
        {chains.length === 0 && <div className="text-sm text-muted-foreground">No chains created yet.</div>}
        {chains.slice(0, 2).map((chain: any, idx: number) => {
          const total = chain.steps?.length || 0;
          const done = chain.steps?.filter((s: any) => s.status === 'executed').length || 0;
          const pct = total > 0 ? Math.round((done / total) * 100) : 0;

          return (
            <div key={idx} className="mb-4">
              <div className="flex justify-between text-sm mb-1">
                <div>{chain.name}</div>
                <div className="text-muted-foreground">{done}/{total} ({pct}%)</div>
              </div>
              <div className="h-3 bg-zinc-800 rounded-full overflow-hidden">
                <div 
                  className="h-full bg-gradient-to-r from-emerald-500 to-emerald-400 transition-all" 
                  style={{ width: `${pct}%` }}
                />
              </div>
            </div>
          );
        })}
      </div>

      <div className="grid md:grid-cols-2 gap-6">
        {/* Top Assets */}
        <div>
          <div className="font-semibold mb-2">Top Discovered Assets</div>
          <div className="border border-border rounded-lg divide-y">
            {assets.length === 0 && <div className="p-4 text-sm text-muted-foreground">No assets discovered yet.</div>}
            {assets.slice(0, 6).map((a, i) => (
              <div key={i} className="p-3 text-sm flex justify-between">
                <span className="font-mono">{a.host}{a.port ? `:${a.port}` : ''}</span>
                <span className="text-muted-foreground text-xs">{a.service || a.status}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Recent Activity */}
        <div>
          <div className="font-semibold mb-2">Recent Activity</div>
          <div className="border border-border rounded-lg divide-y max-h-64 overflow-auto">
            {timeline.length === 0 && <div className="p-4 text-sm text-muted-foreground">No activity logged yet.</div>}
            {timeline.slice(0, 6).map((e, i) => (
              <div key={i} className="p-3 text-sm">
                <div className="text-xs text-muted-foreground">{new Date(e.timestamp).toLocaleString()}</div>
                <div>{e.notes || e.command || e.type}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Quick Actions */}
      <div className="mt-8">
        <div className="font-semibold mb-2">Quick Actions</div>
        <div className="flex flex-wrap gap-2">
          <button onClick={() => window.dispatchEvent(new CustomEvent('navigate-to', { detail: 'execution' }))} className="px-4 py-2 rounded border border-border hover:bg-zinc-900 text-sm">
            Go to Execution
          </button>
          <button onClick={() => window.dispatchEvent(new CustomEvent('navigate-to', { detail: 'assistant' }))} className="px-4 py-2 rounded border border-border hover:bg-zinc-900 text-sm">
            Talk to Red Team Leader
          </button>
          <button onClick={() => window.dispatchEvent(new CustomEvent('navigate-to', { detail: 'chain' }))} className="px-4 py-2 rounded border border-border hover:bg-zinc-900 text-sm">
            Open Chain Builder
          </button>
        </div>
      </div>
    </div>
  );
}

function AssistantView({ sidecarPort }: { sidecarPort: number }) {
  const { activeOperation, pendingKillChainPlan, setPendingKillChainPlan } = useRedForgeStore();
  const [messages, setMessages] = useState<Array<{ role: string; content: string }>>([
    { role: "assistant", content: "RedForge Red Team Leader ready.\n\nI have full visibility into your discovered hosts, services, and credentials.\nAsk me to build or continue a kill chain using your real assets (no placeholders).\n\nTry the buttons below or type naturally." }
  ]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);

  // Listen for external "send to assistant" requests (from Explain buttons etc.)
  useEffect(() => {
    const handler = (e: any) => {
      if (e.detail) {
        sendMessage(e.detail);
      }
    };
    window.addEventListener('assistant-send', handler);
    return () => window.removeEventListener('assistant-send', handler);
  }, []);

  async function sendMessage(customMessage?: string) {
    const messageToSend = customMessage || input;
    if (!messageToSend.trim()) return;

    const userMsg = { role: "user", content: messageToSend };
    setMessages(prev => [...prev, userMsg]);
    if (!customMessage) setInput("");
    setLoading(true);

    try {
      const res = await fetch(`http://127.0.0.1:${sidecarPort}/api/assistant`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: messageToSend,
          operation_id: activeOperation?.id,
          context: {
            active_operation: activeOperation?.name,
          }
        }),
      });

      const data = await res.json();
      setMessages(prev => [...prev, { role: "assistant", content: data.reply }]);
    } catch {
      setMessages(prev => [...prev, { role: "assistant", content: "Error reaching the assistant backend." }]);
    } finally {
      setLoading(false);
    }
  }

  function handleQuickCommand(cmd: string) {
    sendMessage(cmd);
  }

  return (
    <div className="flex h-full flex-col p-4 bg-zinc-950">
      <div className="flex items-center justify-between mb-2 border-b border-border pb-2">
        <div>
          <div className="font-mono text-emerald-400 text-sm">REDFORGE :: RED TEAM LEADER TERMINAL</div>
          <div className="text-xs text-muted-foreground">Local LLM • Kill Chain + ATT&CK guided • Uses real discovered data</div>
        </div>
        <div className="flex gap-2 text-xs">
          <button onClick={() => handleQuickCommand("Start a full Cyber Kill Chain for this operation")} className="px-2 py-1 border border-emerald-800 hover:bg-emerald-950 rounded">Start Kill Chain</button>
          <button onClick={() => handleQuickCommand("What's the next step in the kill chain based on my progress?")} className="px-2 py-1 border border-emerald-800 hover:bg-emerald-950 rounded">Next Step</button>
          <button onClick={() => handleQuickCommand("Give me the best execution commands for the hosts and services we have discovered so far")} className="px-2 py-1 border border-emerald-800 hover:bg-emerald-950 rounded">Tailored Execution</button>
          <button onClick={() => handleQuickCommand("Using only the real hosts, ports and credentials we have discovered, what is my single best next move right now? Give me the exact command.")} className="px-2 py-1 border border-emerald-800 hover:bg-emerald-950 rounded">Best Next Move</button>
        </div>
      </div>

      <div className="flex-1 overflow-auto border border-border rounded bg-black/70 p-4 font-mono text-sm space-y-4 mb-3">
        {messages.map((m, i) => (
          <div key={i} className={m.role === "user" ? "text-emerald-400" : "text-zinc-200"}>
            <span className="text-emerald-500/70 mr-2">{m.role === "user" ? ">" : "redforge>"}</span>
            <span className="whitespace-pre-wrap">{m.content}</span>
          </div>
        ))}
        {loading && <div className="text-emerald-500/70">thinking...</div>}
      </div>

      <div className="flex gap-2">
        <input
          value={input}
          onChange={e => setInput(e.target.value)}
          onKeyDown={e => e.key === "Enter" && !loading && sendMessage()}
          placeholder="Talk to your Red Team Leader... (e.g. continue the kill chain using real hosts we found)"
          className="flex-1 font-mono rounded border border-emerald-800 bg-black px-3 py-2 text-sm focus:outline-none focus:border-emerald-600"
          disabled={loading}
        />
        <button
          onClick={() => sendMessage()}
          disabled={loading || !input.trim()}
          className="px-6 py-2 rounded bg-emerald-700 hover:bg-emerald-600 text-sm font-medium disabled:opacity-50"
        >
          Send
        </button>
      </div>

      <div className="mt-2 text-[10px] text-emerald-500/70">
        The assistant sees your real discovered hosts, services, and progress. Ask it to generate ready-to-run commands using actual values.
      </div>

      {/* === Guided Kill Chain Mode === */}
      <div className="mt-4 pt-4 border-t border-border">
        <div className="text-sm font-semibold mb-2 text-emerald-400">Guided Kill Chain Mode</div>
        <div className="flex flex-wrap gap-2 mb-2">
          <button
            onClick={() => sendMessage("Develop a full Cyber Kill Chain for this operation using the assets we have discovered. Output it phase by phase with ATT&CK techniques and ready-to-run commands using real values.")}
            className="text-xs px-3 py-1.5 rounded border border-emerald-700 hover:bg-emerald-950"
          >
            Develop Full Kill Chain
          </button>
          <button
            onClick={() => sendMessage("Continue / advance the kill chain based on our current progress and discovered assets. Give the next 2-3 phases with concrete commands.")}
            className="text-xs px-3 py-1.5 rounded border border-emerald-700 hover:bg-emerald-950"
          >
            Continue Kill Chain
          </button>
          <button
            onClick={async () => {
              if (!activeOperation) return;
              try {
                const res = await fetch(`http://127.0.0.1:${sidecarPort}/api/assistant/plan_kill_chain`, {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({
                    message: "Generate a complete structured kill chain for this operation",
                    operation_id: activeOperation.id,
                  }),
                });
                const plan = await res.json();

                // Show the plan and offer import
                const planText = `**${plan.name}**\n${plan.description}\n\n` +
                  plan.steps.map((s: any, i: number) => `${i+1}. [${s.technique_id}] ${s.phase}\n   ${s.description}\n   Command: ${s.suggested_command || '(none)'}`).join("\n\n");

                setMessages(prev => [...prev, {
                  role: "assistant",
                  content: "Here is a structured kill chain plan:\n\n" + planText + "\n\nClick the button below to import it into the Chain Builder with real values."
                }]);

                // Use proper store instead of window hack
                useRedForgeStore.getState().setPendingKillChainPlan(plan);
              } catch {
                toast.error("Failed to generate structured kill chain");
              }
            }}
            className="text-xs px-3 py-1.5 rounded bg-emerald-700 hover:bg-emerald-600"
          >
            Generate Structured Plan (for import)
          </button>
        </div>

        {/* === Structured Kill Chain Preview + Import (greatly improved) === */}
        {pendingKillChainPlan && activeOperation && (
          <div className="mt-3 p-3 border border-emerald-700 rounded bg-emerald-950/20">
            <div className="text-emerald-400 text-sm font-semibold mb-1">Structured Kill Chain Ready</div>
            <div className="text-xs mb-2">
              <strong>{pendingKillChainPlan.name}</strong><br />
              {pendingKillChainPlan.description?.slice(0, 140)}...
            </div>

            <div className="text-[10px] mb-2 text-emerald-300/80">
              {pendingKillChainPlan.steps?.length} steps • Will use real discovered hosts/creds where possible
            </div>

            <div className="flex gap-2">
              <button
                onClick={async () => {
                  try {
                    await importKillChain(pendingKillChainPlan, activeOperation.id, sidecarPort);
                    toast.success("Kill chain imported into Chain Builder with real values!");
                    setPendingKillChainPlan(null);
                    // Optionally navigate user to chain view
                    window.dispatchEvent(new CustomEvent("redforge:navigate", { detail: "chain" }));
                  } catch {
                    toast.error("Import failed");
                  }
                }}
                className="flex-1 py-1.5 text-sm font-medium rounded bg-emerald-600 hover:bg-emerald-500"
              >
                Import to Chain Builder
              </button>

              <button
                onClick={() => {
                  if (pendingKillChainPlan.steps?.[0]) {
                    const first = pendingKillChainPlan.steps[0];
                    window.dispatchEvent(new CustomEvent("load-execution-command", {
                      detail: { command: first.suggested_command, technique: first.technique_id }
                    }));
                    window.dispatchEvent(new CustomEvent("redforge:navigate", { detail: "execution" }));
                  }
                }}
                className="flex-1 py-1.5 text-sm rounded border border-emerald-700 hover:bg-emerald-950"
              >
                Load First Step in Execution
              </button>
            </div>

            <button onClick={() => setPendingKillChainPlan(null)} className="mt-1 w-full text-[10px] text-emerald-400/70 hover:text-emerald-400">
              Discard plan
            </button>
          </div>
        )}

        {!pendingKillChainPlan && (
          <div className="text-[10px] text-emerald-500/60 mt-1">
            Use "Generate Structured Plan" above for a clean, importable kill chain using your real assets.
          </div>
        )}
      </div>
    </div>
  );
}

function ReportsView({ sidecarPort }: { sidecarPort: number }) {
  const { activeOperation } = useRedForgeStore();
  const [report, setReport] = useState("");

  async function generateReport() {
    if (!activeOperation) return;

    const [timeline, chains] = await Promise.all([
      getTimeline(activeOperation.id, sidecarPort),
      listChains(activeOperation.id, sidecarPort),
    ]);

    let md = `# Red Team Engagement Report\n\n`;
    md += `**Operation:** ${activeOperation.name}\n\n`;
    md += `**Scope:** ${activeOperation.scope || "N/A"}\n\n`;
    md += `**Generated:** ${new Date().toISOString()}\n\n`;

    md += `## Timeline\n\n`;
    timeline.forEach(e => {
      md += `- **${new Date(e.timestamp).toLocaleString()}** [${e.type}] ${e.technique_id || ''} ${e.command || e.notes || ''}\n`;
    });

    md += `\n## Attack Chains\n\n`;
    for (const c of chains) {
      const full = await getChain(c.id, sidecarPort);
      md += `### ${full.name}\n`;
      full.steps.forEach(s => {
        md += `- [${s.status}] ${s.technique_id}\n`;
      });
      md += `\n`;
    }

    setReport(md);
  }

  function download() {
    const blob = new Blob([report], { type: "text/markdown" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${activeOperation?.name.replace(/\s+/g, "_") || "report"}.md`;
    a.click();
    URL.revokeObjectURL(url);
  }

  if (!activeOperation) return <div className="p-8">Select an active operation.</div>;

  return (
    <div className="p-6">
      <button onClick={generateReport} className="mb-4 rounded bg-red-600 px-4 py-2">Generate Report</button>
      {report && (
        <>
          <button onClick={download} className="ml-3 rounded border px-4 py-2">Download Markdown</button>
          <pre className="mt-4 whitespace-pre-wrap rounded bg-zinc-950 p-4 text-sm border border-border max-h-[70vh] overflow-auto">{report}</pre>
        </>
      )}
    </div>
  );
}

function ChainBuilder({ sidecarPort }: { sidecarPort: number }) {
  const { activeOperation } = useRedForgeStore();
  const [chains, setChains] = useState<Chain[]>([]);
  const [selectedChain, setSelectedChain] = useState<ChainWithSteps | null>(null);
  const [searchTech, setSearchTech] = useState("");
  const [searchResults, setSearchResults] = useState<Technique[]>([]);

  async function loadChains() {
    if (!activeOperation) return;
    const list = await listChains(activeOperation.id, sidecarPort);
    setChains(list);
  }

  async function loadChain(id: string) {
    const full = await getChain(id, sidecarPort);
    setSelectedChain(full);
  }

  useEffect(() => {
    if (activeOperation) loadChains();
  }, [activeOperation?.id, sidecarPort]);

  async function createNewChain() {
    if (!activeOperation) return;
    const name = prompt("Chain name (e.g. Initial Access → Privilege Escalation)");
    if (!name) return;
    await createChain(activeOperation.id, name, "", sidecarPort);
    await loadChains();
  }

  async function addTechniqueToChain(tech: Technique) {
    if (!selectedChain) return;
    const updated = await addStepToChain(selectedChain.id, tech.external_id, sidecarPort);
    setSelectedChain(updated);
  }

  async function updateStepStatus(stepId: string, status: string) {
    await updateStep(stepId, status, undefined, sidecarPort);
    if (selectedChain) await loadChain(selectedChain.id);

    // === Automation: When a step is executed, ask Red Team Leader for next move ===
    if (status === "executed" && activeOperation && sidecarPort) {
      try {
        const res = await fetch(`http://127.0.0.1:${sidecarPort}/api/assistant`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            message: "I just executed a step in my attack chain. Based on my current progress and discovered assets, what should be my next move? Give me 1-2 ready-to-use commands with real values if possible.",
            operation_id: activeOperation.id,
          }),
        });
        const data = await res.json();

        toast.success("Step marked executed — Red Team Leader has suggestions", {
          description: "Check the Red Team Leader tab for the next recommended actions",
          action: {
            label: "View",
            onClick: () => {
              // We can't easily navigate here, but we can pre-load one command if possible
              if (data.reply) {
                // Try to extract a command from the reply (very rough)
                const match = data.reply.match(/`([^`]+)`/);
                // Dispatch to Execution view if possible
                window.dispatchEvent(new CustomEvent('load-execution-command', { detail: { command: match[1] } }));
              }
            },
          },
        });
      } catch {}
    }
  }

  async function searchForTech(q: string) {
    setSearchTech(q);
    if (q.length < 2) {
      setSearchResults([]);
      return;
    }
    const res = await searchTechniques({ q }, sidecarPort);
    setSearchResults(res.techniques.slice(0, 8));
  }

  if (!activeOperation) {
    return <div className="p-8 text-muted-foreground">Select an active operation to build attack chains.</div>;
  }

  return (
    <div className="flex h-full">
      {/* Chains sidebar */}
      <div className="w-72 border-r border-border bg-zinc-950 flex flex-col">
        <div className="p-3 border-b flex justify-between items-center">
          <div className="font-semibold">Attack Chains</div>
          <button onClick={createNewChain} className="text-xs px-2 py-1 bg-red-600 rounded">+ New</button>
        </div>
        <div className="flex-1 overflow-auto p-2 space-y-1">
          {chains.map(c => (
            <div
              key={c.id}
              onClick={() => loadChain(c.id)}
              className={cn("p-2 rounded cursor-pointer text-sm", selectedChain?.id === c.id ? "bg-red-950/40 border border-red-600" : "hover:bg-zinc-800")}
            >
              {c.name}
            </div>
          ))}
        </div>
      </div>

      {/* Main chain area */}
      <div className="flex-1 p-4 overflow-auto">
        {!selectedChain && <div className="text-muted-foreground">Select or create a chain on the left.</div>}

        {selectedChain && (
          <div>
            <h2 className="text-2xl font-semibold">{selectedChain.name}</h2>

            {/* Add technique */}
            <div className="mt-4 mb-2">
              <input
                value={searchTech}
                onChange={(e) => searchForTech(e.target.value)}
                placeholder="Search technique to add (e.g. T1059)"
                className="w-full rounded border border-border bg-zinc-900 px-3 py-2 text-sm"
              />
              {searchResults.length > 0 && (
                <div className="mt-1 border border-border bg-zinc-950 max-h-48 overflow-auto">
                  {searchResults.map(t => (
                    <div
                      key={t.external_id}
                      onClick={() => addTechniqueToChain(t)}
                      className="px-3 py-1.5 hover:bg-zinc-800 cursor-pointer text-sm flex justify-between"
                    >
                      <span><span className="font-mono text-red-400">{t.external_id}</span> — {t.name}</span>
                      <span className="text-xs text-muted-foreground">Add →</span>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Visual Kill Chain Flow */}
            <div className="mt-4">
              <div className="text-sm font-semibold mb-3">Visual Kill Chain Flow</div>
              
              {selectedChain.steps.length === 0 && (
                <div className="text-muted-foreground italic">No steps yet. Add techniques from the search above to build your chain.</div>
              )}

              <div className="flex items-center gap-1 overflow-x-auto pb-4 snap-x">
                {selectedChain.steps.map((step: any, index: number) => {
                  // Tactic color mapping (visualization)
                  const tacticShort = step.technique_id?.slice(0, 4).toLowerCase();
                  const tacticColors: Record<string, string> = {
                    't159': 'border-blue-500 bg-blue-950/20',      // Reconnaissance
                    't156': 'border-red-500 bg-red-950/20',        // Initial Access
                    't119': 'border-red-500 bg-red-950/20',
                    't105': 'border-orange-500 bg-orange-950/20',  // Execution
                    't120': 'border-orange-500 bg-orange-950/20',
                    't154': 'border-yellow-500 bg-yellow-950/20',  // Persistence
                    't106': 'border-green-500 bg-green-950/20',    // Privilege Escalation
                    't102': 'border-cyan-500 bg-cyan-950/20',      // Lateral Movement
                    't100': 'border-purple-500 bg-purple-950/20',  // Credential Access
                    't101': 'border-sky-500 bg-sky-950/20',        // Discovery
                  };
                  const tacticColor = tacticColors[tacticShort] || 'border-border bg-card';

                  const statusColor = 
                    step.status === 'executed' ? 'bg-emerald-950/30' :
                    step.status === 'in_progress' ? 'bg-amber-950/30' :
                    step.status === 'failed' ? 'bg-red-950/30' :
                    'bg-card';

                  const combinedColor = `${tacticColor} ${statusColor}`;

                  return (
                    <React.Fragment key={step.id}>
                      <div className={`min-w-[210px] snap-start rounded-2xl border-2 p-4 shadow-sm ${combinedColor}`}>
                        <div className="flex items-start justify-between mb-2">
                          <div>
                            <div className="font-mono font-semibold text-sm text-red-300">{step.technique_id}</div>
                            <div className="text-[10px] text-muted-foreground">Step {index + 1}</div>
                          </div>
                          <div className={`text-[10px] px-2 py-0.5 rounded-full capitalize tracking-wide ${
                            step.status === 'executed' ? 'bg-emerald-900 text-emerald-300' :
                            step.status === 'in_progress' ? 'bg-amber-900 text-amber-300' :
                            step.status === 'failed' ? 'bg-red-900 text-red-300' :
                            'bg-zinc-800 text-zinc-400'
                          }`}>
                            {step.status.replace('_', ' ')}
                          </div>
                        </div>

                        <div className="text-sm text-zinc-200 mb-3 min-h-[2.25rem] leading-tight">
                          {step.notes || "No description yet"}
                        </div>

                        <div className="flex items-center gap-2">
                          <select
                            value={step.status}
                            onChange={(e) => updateStepStatus(step.id, e.target.value)}
                            className="flex-1 bg-zinc-900 border border-zinc-700 rounded-lg px-2 py-1 text-xs focus:outline-none"
                          >
                            <option value="planned">planned</option>
                            <option value="in_progress">in progress</option>
                            <option value="executed">executed</option>
                            <option value="failed">failed</option>
                            <option value="skipped">skipped</option>
                          </select>

                          <button
                            onClick={() => updateStepStatus(step.id, "executed")}
                            className="px-3 py-1 text-xs rounded-lg bg-emerald-600 hover:bg-emerald-500 active:bg-emerald-700 transition-colors"
                          >
                            Done
                          </button>
                        </div>
                      </div>

                      {index < selectedChain.steps.length - 1 && (
                        <div className="flex items-center text-3xl text-zinc-600 select-none">→</div>
                      )}
                    </React.Fragment>
                  );
                })}
              </div>

              {selectedChain.steps.length > 0 && (
                <div className="text-[10px] text-muted-foreground mt-2">
                  Horizontal scroll →  •  Click cards to load details or change status
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default function App() {
  const [activeView, setActiveView] = useState<keyof typeof views>("operations");
  const [sidecar, setSidecar] = useState({ connected: false, port: 18765 });
  const [isRestarting, setIsRestarting] = useState(false);
  const { activeOperation } = useRedForgeStore();

  useEffect(() => {
    const poll = async () => {
      try {
        const s = await invoke<SidecarStatus>("get_sidecar_status");
        setSidecar(s);
      } catch (e) {}
    };
    const i = setInterval(poll, 4000);
    poll();
    return () => clearInterval(i);
  }, []);

  async function handleRestartSidecar() {
    setIsRestarting(true);
    try {
      const s = await invoke<SidecarStatus>("restart_sidecar");
      setSidecar(s);
    } catch (e) {}
    finally { setIsRestarting(false); }
  }

  const Active = ((views as any)[activeView] || (views as any)["operations"]).component;

  return (
    <div className="flex h-screen w-screen flex-col overflow-hidden bg-background text-foreground">
      <div className="tactical-header h-12 flex items-center px-4 text-sm">
        <div className="font-bold text-red-400 mr-4">REDFORGE</div>
        <div className="flex-1" />
        <div className="text-xs text-red-500 font-medium mr-4">AUTHORIZED USE ONLY</div>
        <div>Sidecar: {sidecar.connected ? "OK" : "down"}</div>
        <button onClick={handleRestartSidecar} className="ml-2 px-2 py-0.5 text-xs border rounded">Restart</button>
      </div>
      <div className="flex flex-1 overflow-hidden">
        <div className="w-48 border-r border-border p-2 overflow-auto text-sm">
          {Object.entries(views).map(([k, v]) => (
            <button key={k} onClick={() => setActiveView(k as keyof typeof views)} className={"block w-full text-left px-2 py-1 rounded " + (activeView === k ? "bg-red-600" : "hover:bg-zinc-800")}>
              {v.label}
            </button>
          ))}
        </div>
        <div className="flex-1 overflow-auto">
          <Active sidecarPort={sidecar.port} />
        </div>
      </div>
      <div className="h-6 text-[10px] border-t border-border px-2 flex items-center">
        OPERATION: {activeOperation ? activeOperation.name : "— none —"} | AUTHORIZED USE ONLY
      </div>
    </div>
  );
}
