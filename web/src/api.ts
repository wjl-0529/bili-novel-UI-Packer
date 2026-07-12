import type {
  AutoUpdateConfig,
  AutoUpdateRunResult,
  CleanupConfig,
  DownloadJob,
  JobRequest,
  NovelPreview,
  NovelPreviewFailure,
  RuntimeInfo,
  WebDavConfig,
} from "./types";

export class HttpError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "HttpError";
    this.status = status;
  }
}

const unauthorizedListeners = new Set<() => void>();

export function subscribeUnauthorized(listener: () => void) {
  unauthorizedListeners.add(listener);
  return () => {
    unauthorizedListeners.delete(listener);
  };
}

async function request<T>(url: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(url, {
    credentials: "same-origin",
    headers: {
      "content-type": "application/json",
      ...options.headers,
    },
    ...options,
  });

  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) {
    const error = new HttpError(
      response.status,
      data.message ?? `请求失败：${response.status}`,
    );
    if (response.status === 401 && url !== "/api/login") {
      unauthorizedListeners.forEach((listener) => listener());
    }
    throw error;
  }
  return data as T;
}

export function login(password: string) {
  return request<{ ok: boolean }>("/api/login", {
    method: "POST",
    body: JSON.stringify({ password }),
  });
}

export function logout() {
  return request<{ ok: boolean }>("/api/logout", { method: "POST" });
}

export function me() {
  return request<{ authenticated: boolean }>("/api/me");
}

export function getRuntime() {
  return request<RuntimeInfo>("/api/runtime");
}

export function getJobs() {
  return request<{ jobs: DownloadJob[] }>("/api/jobs");
}

export function createJobs(body: JobRequest) {
  return request<{ jobs: DownloadJob[] }>("/api/jobs", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function previewNovel(body: JobRequest) {
  return request<{
    previews?: NovelPreview[];
    preview?: NovelPreview;
    previewFailures?: NovelPreviewFailure[];
  }>("/api/novel/preview", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function cancelJob(id: string) {
  return request<{ ok: boolean }>(`/api/jobs/${id}/cancel`, { method: "POST" });
}

export function retryJob(id: string) {
  return request<{ ok: boolean }>(`/api/jobs/${id}/retry`, { method: "POST" });
}

export function deleteJob(id: string) {
  return request<{ ok: boolean }>(`/api/jobs/${id}`, { method: "DELETE" });
}

export function deleteJobOutputs(id: string) {
  return request<{ ok: boolean; job: DownloadJob }>(`/api/jobs/${id}/outputs`, {
    method: "DELETE",
  });
}

export function cleanupCompletedJobs() {
  return request<{ ok: boolean; deleted: number; jobs: DownloadJob[] }>(
    "/api/jobs/cleanup",
    { method: "POST" },
  );
}

export function getCleanupConfig() {
  return request<{ config: CleanupConfig }>("/api/cleanup/config");
}

export function saveCleanupConfig(body: CleanupConfig) {
  return request<{ ok: boolean; config: CleanupConfig }>("/api/cleanup/config", {
    method: "PUT",
    body: JSON.stringify(body),
  });
}

export function getAutoUpdateConfig() {
  return request<{ config: AutoUpdateConfig }>("/api/auto-update/config");
}

export function saveAutoUpdateConfig(body: AutoUpdateConfig) {
  return request<{ ok: boolean; config: AutoUpdateConfig }>(
    "/api/auto-update/config",
    {
      method: "PUT",
      body: JSON.stringify(body),
    },
  );
}

export function runAutoUpdateNow() {
  return request<{
    ok: boolean;
    result: AutoUpdateRunResult;
    config: AutoUpdateConfig;
  }>("/api/auto-update/run", { method: "POST" });
}

export function getWebDavConfig() {
  return request<{ config: WebDavConfig }>("/api/webdav/config");
}

export function saveWebDavConfig(body: WebDavConfig) {
  return request<{ ok: boolean; config: WebDavConfig }>("/api/webdav/config", {
    method: "PUT",
    body: JSON.stringify(body),
  });
}

export function testWebDavConfig(body: WebDavConfig) {
  return request<{ ok: boolean }>("/api/webdav/test", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export function fileUrl(jobId: string, fileName: string) {
  return `/api/jobs/${jobId}/files/${encodeURIComponent(fileName)}`;
}
