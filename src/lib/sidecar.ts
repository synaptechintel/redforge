/**
 * Simple client for talking directly to the Python sidecar over HTTP.
 * The port is provided by the Rust side via get_sidecar_status.
 */

const DEFAULT_PORT = 18765;

function getBaseUrl(port?: number): string {
  return `http://127.0.0.1:${port ?? DEFAULT_PORT}`;
}

export interface Operation {
  id: string;
  name: string;
  description?: string | null;
  scope?: string | null;
  roe_notes?: string | null;
  status: string;
  created_at: string;
  updated_at: string;
  metadata: Record<string, unknown>;
}

export interface OperationCreate {
  name: string;
  description?: string | null;
  scope?: string | null;
  roe_notes?: string | null;
}

export interface OperationUpdate {
  name?: string | null;
  description?: string | null;
  scope?: string | null;
  roe_notes?: string | null;
  status?: string | null;
}

export async function listOperations(port?: number): Promise<Operation[]> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations`);
  if (!res.ok) throw new Error(`Failed to list operations: ${res.status}`);
  return res.json();
}

export async function createOperation(data: OperationCreate, port?: number): Promise<Operation> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) throw new Error(`Failed to create operation: ${res.status}`);
  return res.json();
}

export async function updateOperation(id: string, data: OperationUpdate, port?: number): Promise<Operation> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${id}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) throw new Error(`Failed to update operation: ${res.status}`);
  return res.json();
}

export async function deleteOperation(id: string, port?: number): Promise<void> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${id}`, {
    method: "DELETE",
  });
  if (!res.ok) throw new Error(`Failed to delete operation: ${res.status}`);
}

// ---------------------------------------------------------------------------
// ATT&CK (Phase 1)
// ---------------------------------------------------------------------------

export interface AttackStats {
  loaded: boolean;
  total_techniques: number;
  total_tactics: number;
  total_objects_in_bundle: number;
  platforms: string[];
}

export interface Technique {
  id: string;
  external_id: string;
  name: string;
  description: string;
  tactics: string[];
  platforms: string[];
  permissions_required: string[];
  data_sources: string[];
  detection: string;
  url: string;
  is_subtechnique: boolean;
}

export interface Tactic {
  id: string;
  external_id: string;
  name: string;
  description: string;
  short_name: string;
  url: string;
}

export async function getAttackStats(port?: number): Promise<AttackStats> {
  const res = await fetch(`${getBaseUrl(port)}/api/attack/stats`);
  if (!res.ok) throw new Error("Failed to load ATT&CK stats");
  return res.json();
}

export async function listTactics(port?: number): Promise<Tactic[]> {
  const res = await fetch(`${getBaseUrl(port)}/api/attack/tactics`);
  if (!res.ok) throw new Error("Failed to load tactics");
  return res.json();
}

export async function searchTechniques(
  params: { q?: string; tactic?: string; platform?: string; limit?: number } = {},
  port?: number
): Promise<{ count: number; techniques: Technique[] }> {
  const usp = new URLSearchParams();
  if (params.q) usp.set("q", params.q);
  if (params.tactic) usp.set("tactic", params.tactic);
  if (params.platform) usp.set("platform", params.platform);
  if (params.limit) usp.set("limit", String(params.limit));

  const res = await fetch(`${getBaseUrl(port)}/api/attack/techniques?${usp}`);
  if (!res.ok) throw new Error("Failed to search techniques");
  return res.json();
}

export async function getTechnique(externalId: string, port?: number): Promise<Technique> {
  const res = await fetch(`${getBaseUrl(port)}/api/attack/techniques/${externalId}`);
  if (!res.ok) throw new Error("Technique not found");
  return res.json();
}

// ---------------------------------------------------------------------------
// Timeline / Execution Log
// ---------------------------------------------------------------------------

export interface TimelineEvent {
  id: string;
  operation_id: string;
  timestamp: string;
  type: string;
  technique_id?: string | null;
  command?: string | null;
  output?: string | null;
  result?: string | null;
  notes?: string | null;
  metadata: Record<string, unknown>;
}

export interface TimelineEventCreate {
  type?: string;
  technique_id?: string | null;
  command?: string | null;
  output?: string | null;
  result?: string | null;
  notes?: string | null;
  metadata?: Record<string, unknown>;
}

export async function getTimeline(opId: string, port?: number): Promise<TimelineEvent[]> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${opId}/timeline`);
  if (!res.ok) throw new Error("Failed to load timeline");
  return res.json();
}

export async function logTimelineEvent(opId: string, data: TimelineEventCreate, port?: number): Promise<TimelineEvent> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${opId}/timeline`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) throw new Error("Failed to log timeline event");
  return res.json();
}

// ---------------------------------------------------------------------------
// Attack Chain Builder
// ---------------------------------------------------------------------------

export interface Chain {
  id: string;
  operation_id: string;
  name: string;
  description?: string | null;
  created_at: string;
  updated_at: string;
}

export interface ChainStep {
  id: string;
  chain_id: string;
  position: number;
  technique_id: string;
  status: string;
  notes?: string | null;
}

export interface ChainWithSteps extends Chain {
  steps: ChainStep[];
}

export async function createChain(opId: string, name: string, description?: string, port?: number): Promise<Chain> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${opId}/chains`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, description }),
  });
  if (!res.ok) throw new Error("Failed to create chain");
  return res.json();
}

export async function listChains(opId: string, port?: number): Promise<Chain[]> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${opId}/chains`);
  if (!res.ok) throw new Error("Failed to load chains");
  return res.json();
}

export async function getChain(chainId: string, port?: number): Promise<ChainWithSteps> {
  const res = await fetch(`${getBaseUrl(port)}/api/chains/${chainId}`);
  if (!res.ok) throw new Error("Failed to load chain");
  return res.json();
}

export async function addStepToChain(chainId: string, techniqueId: string, port?: number): Promise<ChainWithSteps> {
  const res = await fetch(`${getBaseUrl(port)}/api/chains/${chainId}/steps`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ technique_id: techniqueId }),
  });
  if (!res.ok) throw new Error("Failed to add step");
  return res.json();
}

export async function updateStep(stepId: string, status: string, notes?: string, port?: number): Promise<any> {
  const res = await fetch(`${getBaseUrl(port)}/api/steps/${stepId}?status=${status}${notes ? `&notes=${encodeURIComponent(notes)}` : ''}`, {
    method: "PATCH",
  });
  if (!res.ok) throw new Error("Failed to update step");
  return res.json();
}

export async function deleteChain(chainId: string, port?: number): Promise<void> {
  const res = await fetch(`${getBaseUrl(port)}/api/chains/${chainId}`, { method: "DELETE" });
  if (!res.ok) throw new Error("Failed to delete chain");
}

export async function importKillChain(plan: any, operationId: string, port?: number): Promise<any> {
  const res = await fetch(`${getBaseUrl(port)}/api/chains/import?operation_id=${operationId}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(plan),
  });
  if (!res.ok) throw new Error("Failed to import kill chain");
  return res.json();
}

// ---------------------------------------------------------------------------
// Real Local Execution
// ---------------------------------------------------------------------------

export interface ExecuteRequest {
  command: string;
  operation_id?: string | null;
  technique_id?: string | null;
  notes?: string | null;
}

export interface ExecuteResponse {
  success: boolean;
  exit_code: number | null;
  stdout: string;
  stderr: string;
  duration_ms: number;
  logged: boolean;
  method?: string;
  extracted_assets?: number;
  extracted_creds?: number;
}

export async function executeLocalCommand(req: ExecuteRequest, port?: number): Promise<ExecuteResponse> {
  const res = await fetch(`${getBaseUrl(port)}/api/execute`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(req),
  });
  if (!res.ok) throw new Error("Execution failed on sidecar");
  return res.json();
}

export async function basicReconScan(target: string, ports?: string, operationId?: string, port?: number) {
  const res = await fetch(`${getBaseUrl(port)}/api/recon/scan`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      target,
      ports: ports || "22,80,443,445,3389,5985",
      operation_id: operationId,
    }),
  });
  if (!res.ok) throw new Error("Recon scan failed");
  return res.json();
}

// ---------------------------------------------------------------------------
// Output → Next Command Generator
// ---------------------------------------------------------------------------

export interface GenerateFollowupRequest {
  output: string;
  previous_command?: string;
  technique_id?: string;
  target_os?: "windows" | "linux";
  execution_method?: string;
  output_type?: "command" | "script";
  scenario?: string;
}

export interface GenerateFollowupResponse {
  suggested_command: string;
  suggested_type: string;
  explanation: string;
  technique?: string | null;
  extracted_targets?: string[];
  suggested_tools?: string[];
}

export async function generateNextCommand(req: GenerateFollowupRequest, port?: number): Promise<GenerateFollowupResponse> {
  const res = await fetch(`${getBaseUrl(port)}/api/generate_followup`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(req),
  });
  if (!res.ok) throw new Error("Failed to generate follow-up command");
  return res.json();
}

// ---------------------------------------------------------------------------
// RECON + ASSETS (core of the recon → assets → suggestions loop)
// ---------------------------------------------------------------------------

export interface Asset {
  id: string;
  operation_id: string;
  host: string;
  port: number | null;
  service: string | null;
  protocol: string | null;
  status: string | null;
  notes: string | null;
  first_seen: string;
  last_seen: string;
  metadata: Record<string, unknown>;
}

export async function listAssets(operationId: string, port?: number): Promise<Asset[]> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${operationId}/assets`);
  if (!res.ok) throw new Error("Failed to list assets");
  return res.json();
}

export async function createAsset(operationId: string, asset: Partial<Asset>, port?: number): Promise<any> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${operationId}/assets`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(asset),
  });
  if (!res.ok) throw new Error("Failed to create asset");
  return res.json();
}

export async function bulkCreateAssets(operationId: string, items: Array<Partial<Asset>>, port?: number): Promise<{ saved: number; total: number }> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${operationId}/assets/bulk`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(items),
  });
  if (!res.ok) throw new Error("Bulk asset create failed");
  return res.json();
}

export interface ReconResult {
  target: string;
  open_ports?: Array<{ host: string; port: number; status?: string }>;
  assets?: Array<{ host: string; port: number; service?: string; protocol?: string; source?: string }>;
  count?: number;
  saved_to_assets?: number;
  tool?: string;
  error?: string;
}

export async function reconExecute(target: string, ports: string, operationId?: string, tool: string = "python", port?: number): Promise<ReconResult> {
  const res = await fetch(`${getBaseUrl(port)}/api/recon/execute`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ target, ports, operation_id: operationId, tool }),
  });
  if (!res.ok) throw new Error("Recon execute failed");
  return res.json();
}

export async function reconParse(rawOutput: string, operationId?: string, sourceHint?: string, port?: number): Promise<{ count: number; saved: number; assets: any[] }> {
  const res = await fetch(`${getBaseUrl(port)}/api/recon/parse`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ raw_output: rawOutput, operation_id: operationId, source_hint: sourceHint }),
  });
  if (!res.ok) throw new Error("Recon parse failed");
  return res.json();
}

export async function listCredentials(operationId: string, port?: number): Promise<any[]> {
  const res = await fetch(`${getBaseUrl(port)}/api/operations/${operationId}/credentials`);
  if (!res.ok) throw new Error("Failed to list credentials");
  return res.json();
}

export interface RemoteTestRequest {
  host: string;
  username: string;
  password?: string | null;
  hash?: string | null;
  domain?: string;
  execution_method?: "winrm" | "psexec";
  port?: number | null;
  operation_id?: string | null;
}

export interface RemoteTestResponse {
  success: boolean;
  method: string;
  host: string;
  user?: string | null;
  hostname?: string | null;
  os_info?: string | null;
  domain_info?: string | null;
  raw_output: string;
  stderr: string;
  duration_ms: number;
  extracted_assets: number;
  extracted_creds: number;
  tips: string[];
}

export async function testRemoteAccess(req: RemoteTestRequest, port?: number): Promise<RemoteTestResponse> {
  const res = await fetch(`${getBaseUrl(port)}/api/remote/test`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(req),
  });
  if (!res.ok) throw new Error("Remote test failed");
  return res.json();
}
