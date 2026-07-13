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
  const headers = new Headers(options.headers);
  if (options.body !== undefined && !headers.has("content-type")) {
    headers.set("content-type", "application/json");
  }

  let response: Response;
  try {
    response = await fetch(url, {
      credentials: "same-origin",
      ...options,
      headers,
    });
  } catch {
    throw new Error("无法连接服务器，请检查服务是否正在运行");
  }

  const text = await response.text();
  let data: unknown = {};
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      if (response.ok) {
        throw new HttpError(response.status, "服务器返回了无法解析的数据");
      }
      data = { message: text.trim() };
    }
  }
  if (!response.ok) {
    const message =
      typeof data === "object" &&
      data !== null &&
      "message" in data &&
      typeof data.message === "string"
        ? data.message
        : `请求失败：${response.status}`;
    const error = new HttpError(
      response.status,
      message,
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
