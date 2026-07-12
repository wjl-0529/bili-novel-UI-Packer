import {
  Bell,
  CheckCircle2,
  CloudUpload,
  Clock3,
  Download,
  FileText,
  KeyRound,
  ListOrdered,
  Loader2,
  LogOut,
  Play,
  Save,
  RotateCcw,
  Search,
  Server,
  Settings,
  ShieldCheck,
  StopCircle,
  Trash2,
  Wifi,
  WifiOff,
  XCircle,
  type LucideIcon,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { FormEvent, MouseEvent, ReactNode } from "react";
import {
  cancelJob,
  cleanupCompletedJobs,
  createJobs,
  deleteJob,
  deleteJobOutputs,
  fileUrl,
  getAutoUpdateConfig,
  getCleanupConfig,
  getJobs,
  getRuntime,
  getWebDavConfig,
  login,
  logout,
  me,
  previewNovel,
  retryJob,
  runAutoUpdateNow,
  saveAutoUpdateConfig,
  saveCleanupConfig,
  saveWebDavConfig,
  subscribeUnauthorized,
  testWebDavConfig,
} from "./api";
import type {
  AutoUpdateConfig,
  AutoUpdateItem,
  BarkConfig,
  CleanupConfig,
  DownloadJob,
  EventMessage,
  JobRequest,
  JobStatus,
  NovelPreview,
  NovelPreviewFailure,
  RuntimeInfo,
  WebDavConfig,
} from "./types";

type RealtimeState = "connecting" | "connected" | "offline";
type AppView = "workspace" | "settings";
type MobileTab = "download" | "jobs" | "detail" | "settings";
type UploadStatus = NonNullable<DownloadJob["uploadStatus"]>;
type UploadDisplayStatus = UploadStatus | "not-uploaded";

type UploadDisplay = {
  status: UploadDisplayStatus;
  label: string;
  description?: string;
};

type JobStats = {
  total: number;
  running: number;
  queued: number;
  failed: number;
  done: number;
};

type PreviewState = {
  signature: string;
  previews: NovelPreview[];
  failures: NovelPreviewFailure[];
};

const barkStorageKey = "bili-novel-packer:bark-config";

const defaultBark: BarkConfig = {
  enabled: false,
  serverUrl: "https://api.day.app",
  deviceKey: "",
  events: {
    start: false,
    success: true,
    failure: true,
    progress: false,
    update: true,
  },
  progressThrottleSeconds: 300,
};

const defaultWebDavConfig: WebDavConfig = {
  enabled: false,
  serverUrl: "",
  username: "",
  password: "",
  basePath: "/小说/轻小说打包器",
  hasPassword: false,
};

const defaultCleanupConfig: CleanupConfig = {
  enabled: false,
  retentionDays: 7,
};

const defaultAutoUpdateConfig: AutoUpdateConfig = {
  enabled: false,
  dailyTime: "03:00",
  items: [],
};

const defaultRequest: JobRequest = {
  urlTemplate: "https://www.bilinovel.com/novel/{id}.html",
  rangeText: "1-3",
  volumeRangeText: "",
  combineVolume: false,
  addChapterTitle: false,
  barkConfig: defaultBark,
};

function createDefaultRequest(): JobRequest {
  return {
    ...defaultRequest,
    barkConfig: readStoredBarkConfig(),
  };
}

export function App() {
  const [authenticated, setAuthenticated] = useState<boolean | null>(null);
  const [runtimeInfo, setRuntimeInfo] = useState<RuntimeInfo>({
    embedded: false,
    platform: null,
  });
  const [jobs, setJobs] = useState<DownloadJob[]>([]);
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);
  const [appView, setAppView] = useState<AppView>("workspace");
  const [mobileTab, setMobileTab] = useState<MobileTab>("download");
  const [request, setRequest] = useState<JobRequest>(createDefaultRequest);
  const [webDavConfig, setWebDavConfig] = useState<WebDavConfig>(defaultWebDavConfig);
  const [webDavBusy, setWebDavBusy] = useState(false);
  const [webDavNotice, setWebDavNotice] = useState("");
  const [autoCleanupConfig, setAutoCleanupConfig] =
    useState<CleanupConfig>(defaultCleanupConfig);
  const [autoCleanupBusy, setAutoCleanupBusy] = useState(false);
  const [autoCleanupNotice, setAutoCleanupNotice] = useState("");
  const [autoUpdateConfig, setAutoUpdateConfig] =
    useState<AutoUpdateConfig>(defaultAutoUpdateConfig);
  const [autoUpdateBusy, setAutoUpdateBusy] = useState(false);
  const [autoUpdateRunBusy, setAutoUpdateRunBusy] = useState(false);
  const [autoUpdateNotice, setAutoUpdateNotice] = useState("");
  const [password, setPassword] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [cleanupBusy, setCleanupBusy] = useState(false);
  const [previewBusy, setPreviewBusy] = useState(false);
  const [previewState, setPreviewState] = useState<PreviewState | null>(null);
  const [selectedPreviewIds, setSelectedPreviewIds] = useState<Set<number>>(
    () => new Set(),
  );
  const [actionJobIds, setActionJobIds] = useState<Set<string>>(() => new Set());
  const [realtimeState, setRealtimeState] = useState<RealtimeState>("connecting");
  const preferredSelectedJobId = useRef<string | null>(null);

  const clearLocalSession = useCallback(() => {
    preferredSelectedJobId.current = null;
    setAuthenticated(false);
    setJobs([]);
    setSelectedJobId(null);
    setAutoUpdateConfig(defaultAutoUpdateConfig);
    setAppView("workspace");
    setMobileTab("download");
  }, []);

  const selectedJob = useMemo(
    () => jobs.find((job) => job.id === selectedJobId) ?? jobs[0],
    [jobs, selectedJobId],
  );

  const activePreviewSignature = useMemo(
    () => previewSignature(request),
    [request],
  );

  const previewMatchesForm =
    previewState !== null && previewState.signature === activePreviewSignature;

  const currentPreviewAvailable =
    previewState !== null && previewMatchesForm && previewState.previews.length > 0;

  const selectedPreviews = useMemo(() => {
    if (!currentPreviewAvailable || previewState === null) {
      return [];
    }
    return previewState.previews.filter((preview) =>
      selectedPreviewIds.has(preview.sourceId),
    );
  }, [currentPreviewAvailable, previewState, selectedPreviewIds]);

  const previewSelectionEmpty =
    currentPreviewAvailable && selectedPreviews.length === 0;

  const submitRequest = useMemo<JobRequest>(() => {
    if (!currentPreviewAvailable || selectedPreviews.length === 0) {
      return request;
    }
    return {
      ...request,
      rangeText: selectedPreviews.map((preview) => preview.sourceId).join(","),
    };
  }, [currentPreviewAvailable, request, selectedPreviews]);

  const stats = useMemo<JobStats>(() => {
    return {
      total: jobs.length,
      running: jobs.filter((job) => job.status === "running").length,
      queued: jobs.filter((job) => job.status === "queued").length,
      failed: jobs.filter((job) => job.status === "failed").length,
      done: jobs.filter((job) => job.status === "succeeded").length,
    };
  }, [jobs]);

  const cleanupCount = useMemo(
    () => jobs.filter(isCleanupTarget).length,
    [jobs],
  );

  const applyJobsSnapshot = useCallback((nextJobs: DownloadJob[]) => {
    setJobs(nextJobs);
    setSelectedJobId((selected) => {
      const preferred = preferredSelectedJobId.current;
      if (preferred && nextJobs.some((job) => job.id === preferred)) {
        preferredSelectedJobId.current = null;
        return preferred;
      }
      if (selected && nextJobs.some((job) => job.id === selected)) {
        return selected;
      }
      return nextJobs[0]?.id ?? null;
    });
  }, []);

  const refreshJobs = useCallback(async () => {
    const response = await getJobs();
    applyJobsSnapshot(response.jobs);
  }, [applyJobsSnapshot]);

  const refreshWebDavConfig = useCallback(async () => {
    const response = await getWebDavConfig();
    setWebDavConfig({ ...defaultWebDavConfig, ...response.config, password: "" });
  }, []);

  const refreshCleanupConfig = useCallback(async () => {
    const response = await getCleanupConfig();
    setAutoCleanupConfig({ ...defaultCleanupConfig, ...response.config });
  }, []);

  const refreshAutoUpdateConfig = useCallback(async () => {
    const response = await getAutoUpdateConfig();
    setAutoUpdateConfig({
      ...defaultAutoUpdateConfig,
      ...response.config,
      items: response.config.items ?? [],
    });
  }, []);

  useEffect(() => subscribeUnauthorized(clearLocalSession), [clearLocalSession]);

  useEffect(() => {
    let active = true;

    const initialize = async () => {
      try {
        const runtime = await getRuntime();
        if (!active) {
          return;
        }
        setRuntimeInfo(runtime);
        const response = await me();
        if (!active) {
          return;
        }
        setAuthenticated(response.authenticated);
        if (!response.authenticated) {
          return;
        }
        await Promise.allSettled([
          refreshJobs(),
          refreshWebDavConfig(),
          refreshCleanupConfig(),
          refreshAutoUpdateConfig(),
        ]);
      } catch {
        if (active) {
          setAuthenticated(false);
        }
      }
    };

    void initialize();
    return () => {
      active = false;
    };
  }, [refreshJobs, refreshWebDavConfig, refreshCleanupConfig, refreshAutoUpdateConfig]);

  useEffect(() => {
    writeStoredBarkConfig(request.barkConfig);
  }, [request.barkConfig]);

  useEffect(() => {
    if (!authenticated) {
      return;
    }

    setRealtimeState("connecting");
    const source = new EventSource("/api/events");
    let lastRealtimeEventAt = Date.now();
    let fallbackTimer: number | undefined;
    let fallbackPollInFlight = false;
    let realtimeRevision = 0;
    let disposed = false;
    const fallbackIntervalMs = 1500;
    const staleRealtimeMs = 8000;

    const stopFallback = () => {
      if (fallbackTimer !== undefined) {
        window.clearInterval(fallbackTimer);
        fallbackTimer = undefined;
      }
    };

    const pollFallback = async () => {
      if (disposed || fallbackPollInFlight) {
        return;
      }
      fallbackPollInFlight = true;
      const revisionAtStart = realtimeRevision;
      try {
        const response = await getJobs();
        if (!disposed && revisionAtStart === realtimeRevision) {
          applyJobsSnapshot(response.jobs);
        }
      } catch {
        // A 401 is handled by subscribeUnauthorized; other failures retry later.
      } finally {
        fallbackPollInFlight = false;
      }
    };

    const startFallback = () => {
      if (disposed || fallbackTimer !== undefined) {
        return;
      }
      void pollFallback();
      fallbackTimer = window.setInterval(() => {
        void pollFallback();
      }, fallbackIntervalMs);
    };

    const watchdogTimer = window.setInterval(() => {
      if (Date.now() - lastRealtimeEventAt > staleRealtimeMs) {
        setRealtimeState("offline");
        startFallback();
      }
    }, 3000);

    source.onopen = () => {
      realtimeRevision += 1;
      lastRealtimeEventAt = Date.now();
      setRealtimeState("connected");
      stopFallback();
    };

    source.onerror = () => {
      setRealtimeState("offline");
      startFallback();
    };

    source.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data) as EventMessage;
        realtimeRevision += 1;
        lastRealtimeEventAt = Date.now();
        setRealtimeState("connected");
        stopFallback();
        if (message.type === "jobs") {
          applyJobsSnapshot(message.data);
        }
        if (message.type === "job") {
          setJobs((current) => upsertJob(current, message.data));
          setSelectedJobId((selected) => selected ?? message.data.id);
        }
        if (message.type === "jobDeleted") {
          removeJobFromState(message.data.id);
        }
        if (message.type === "heartbeat") {
          return;
        }
      } catch {
        setRealtimeState("offline");
        startFallback();
      }
    };

    return () => {
      disposed = true;
      window.clearInterval(watchdogTimer);
      stopFallback();
      source.close();
    };
  }, [authenticated, applyJobsSnapshot]);

  useEffect(() => {
    const preferred = preferredSelectedJobId.current;
    if (!preferred) {
      return;
    }
    if (!jobs.some((job) => job.id === preferred)) {
      return;
    }
    if (selectedJobId !== preferred) {
      setSelectedJobId(preferred);
      return;
    }
    preferredSelectedJobId.current = null;
  }, [jobs, selectedJobId]);

  async function handleLogin(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setNotice("");
    try {
      await login(password);
      setAuthenticated(true);
      await Promise.all([
        refreshJobs(),
        refreshWebDavConfig(),
        refreshCleanupConfig(),
        refreshAutoUpdateConfig(),
      ]);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "登录失败");
    } finally {
      setBusy(false);
    }
  }

  async function handleLogout() {
    try {
      await logout();
    } catch {
      // Local logout must still work when the session has expired or the server is offline.
    } finally {
      clearLocalSession();
    }
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (previewSelectionEmpty) {
      setNotice("请至少勾选一本搜索结果，或修改范围后直接开始下载。");
      return;
    }
    setBusy(true);
    setNotice("");
    const usingPreviewIds = currentPreviewAvailable && selectedPreviews.length > 0;
    try {
      const response = await createJobs(submitRequest);
      const nextSelectedJobId = response.jobs[0]?.id ?? null;
      preferredSelectedJobId.current = nextSelectedJobId;
      setJobs((current) => mergeNewJobs(current, response.jobs));
      setSelectedJobId(nextSelectedJobId);
      setMobileTab("jobs");
      setNotice(
        usingPreviewIds
          ? `已按勾选结果创建 ${response.jobs.length} 个任务`
          : `已按顺序创建 ${response.jobs.length} 个任务`,
      );
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "创建任务失败");
    } finally {
      setBusy(false);
    }
  }

  async function handlePreview() {
    setNotice("");
    setPreviewState(null);
    setPreviewBusy(true);
    try {
      const response = await previewNovel(request);
      const nextPreviews = response.previews ?? (response.preview ? [response.preview] : []);
      const failures = response.previewFailures ?? [];
      setPreviewState({
        signature: activePreviewSignature,
        previews: nextPreviews,
        failures,
      });
      setSelectedPreviewIds(new Set(nextPreviews.map((preview) => preview.sourceId)));
      if (nextPreviews.length === 0) {
        setNotice("未找到可预览的小说");
        return;
      }
      setNotice(
        failures.length > 0
          ? `已找到 ${nextPreviews.length} 本小说，跳过 ${failures.length} 个无结果 ID`
          : nextPreviews.length === 1
            ? `已找到《${nextPreviews[0].title}》`
            : `已找到 ${nextPreviews.length} 本小说`,
      );
    } catch (error) {
      setPreviewState(null);
      setSelectedPreviewIds(new Set());
      setNotice(error instanceof Error ? error.message : "搜索小说失败");
    } finally {
      setPreviewBusy(false);
    }
  }

  function handlePreviewSelection(sourceId: number, selected: boolean) {
    setSelectedPreviewIds((current) => {
      const next = new Set(current);
      if (selected) {
        next.add(sourceId);
      } else {
        next.delete(sourceId);
      }
      return next;
    });
  }

  function handleSelectAllPreviews() {
    if (previewState === null || !previewMatchesForm) {
      return;
    }
    setSelectedPreviewIds(new Set(previewState.previews.map((preview) => preview.sourceId)));
  }

  function handleClearPreviewSelection() {
    setSelectedPreviewIds(new Set());
  }

  function handleSelectJob(jobId: string) {
    setSelectedJobId(jobId);
    setMobileTab("detail");
  }

  async function handleCancel(job: DownloadJob) {
    setNotice("");
    markAction(job.id, true);
    setJobs((current) =>
      patchJob(current, job.id, {
        status: "canceled",
        message: "任务已取消",
      }),
    );
    try {
      await cancelJob(job.id);
      setNotice("任务已取消");
      await refreshJobs();
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "取消任务失败");
      await refreshJobs().catch(() => undefined);
    } finally {
      markAction(job.id, false);
    }
  }

  async function handleRetry(job: DownloadJob) {
    setNotice("");
    markAction(job.id, true);
    setJobs((current) =>
      patchJob(current, job.id, {
        status: "queued",
        progress: 0,
        message: "已重新加入队列",
        error: undefined,
        outputFiles: [],
        uploadStatus: webDavConfig.enabled ? "pending" : "disabled",
        uploadedFiles: [],
        uploadError: undefined,
      }),
    );
    try {
      await retryJob(job.id);
      setNotice("已重新加入队列");
      await refreshJobs();
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "重试任务失败");
      await refreshJobs().catch(() => undefined);
    } finally {
      markAction(job.id, false);
    }
  }

  async function handleDelete(job: DownloadJob) {
    setNotice("");
    markAction(job.id, true);
    removeJobFromState(job.id);
    try {
      await deleteJob(job.id);
      setNotice(`已删除任务 #${job.sourceId}`);
      await refreshJobs();
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "删除任务失败");
      await refreshJobs().catch(() => undefined);
    } finally {
      markAction(job.id, false);
    }
  }

  async function handleDeleteOutputs(job: DownloadJob) {
    if (job.outputFiles.length === 0) {
      setNotice("当前任务没有可清理的输出文件");
      return;
    }
    const ok = window.confirm(
      `删除任务 #${job.sourceId} 的 ${job.outputFiles.length} 个输出文件？任务记录和日志会保留。`,
    );
    if (!ok) {
      return;
    }
    setNotice("");
    markAction(job.id, true);
    try {
      const response = await deleteJobOutputs(job.id);
      setJobs((current) => upsertJob(current, response.job));
      setNotice(`已清理任务 #${job.sourceId} 的输出文件`);
      await refreshJobs();
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "清理输出文件失败");
      await refreshJobs().catch(() => undefined);
    } finally {
      markAction(job.id, false);
    }
  }

  async function handleSaveWebDavConfig(clearPassword = false) {
    setWebDavBusy(true);
    setWebDavNotice("");
    try {
      const response = await saveWebDavConfig({
        ...webDavConfig,
        clearPassword,
        password: clearPassword ? "" : webDavConfig.password ?? "",
      });
      setWebDavConfig({ ...defaultWebDavConfig, ...response.config, password: "" });
      setWebDavNotice(clearPassword ? "WebDAV 密码已清空" : "WebDAV 设置已保存");
    } catch (error) {
      setWebDavNotice(error instanceof Error ? error.message : "WebDAV 设置保存失败");
    } finally {
      setWebDavBusy(false);
    }
  }

  async function handleTestWebDavConfig() {
    setWebDavBusy(true);
    setWebDavNotice("");
    try {
      await testWebDavConfig(webDavConfig);
      setWebDavNotice("WebDAV 连接测试通过");
    } catch (error) {
      setWebDavNotice(error instanceof Error ? error.message : "WebDAV 连接测试失败");
    } finally {
      setWebDavBusy(false);
    }
  }

  async function handleSaveCleanupConfig() {
    setAutoCleanupBusy(true);
    setAutoCleanupNotice("");
    try {
      const response = await saveCleanupConfig({
        enabled: autoCleanupConfig.enabled,
        retentionDays: Math.max(
          1,
          Math.min(365, Math.round(autoCleanupConfig.retentionDays || 7)),
        ),
      });
      setAutoCleanupConfig({ ...defaultCleanupConfig, ...response.config });
      setAutoCleanupNotice("自动清理设置已保存");
    } catch (error) {
      setAutoCleanupNotice(error instanceof Error ? error.message : "自动清理设置保存失败");
    } finally {
      setAutoCleanupBusy(false);
    }
  }

  async function handleSaveAutoUpdateConfig() {
    setAutoUpdateBusy(true);
    setAutoUpdateNotice("");
    try {
      const response = await saveAutoUpdateConfig({
        enabled: autoUpdateConfig.enabled,
        dailyTime: normalizeTimeInput(autoUpdateConfig.dailyTime),
        lastRunAt: autoUpdateConfig.lastRunAt,
        items: autoUpdateConfig.items.map((item) => ({
          ...item,
          enabled: item.enabled !== false,
        })),
      });
      setAutoUpdateConfig({
        ...defaultAutoUpdateConfig,
        ...response.config,
        items: response.config.items ?? [],
      });
      setAutoUpdateNotice("自动更新设置已保存");
    } catch (error) {
      setAutoUpdateNotice(error instanceof Error ? error.message : "自动更新设置保存失败");
    } finally {
      setAutoUpdateBusy(false);
    }
  }

  async function handleRunAutoUpdateNow() {
    setAutoUpdateRunBusy(true);
    setAutoUpdateNotice("");
    try {
      const response = await runAutoUpdateNow();
      setAutoUpdateConfig({
        ...defaultAutoUpdateConfig,
        ...response.config,
        items: response.config.items ?? [],
      });
      setAutoUpdateNotice(
        `已检查 ${response.result.checked} 个任务，更新 ${response.result.updated} 个`,
      );
      await refreshJobs();
    } catch (error) {
      setAutoUpdateNotice(error instanceof Error ? error.message : "手动检查失败");
      await refreshJobs().catch(() => undefined);
    } finally {
      setAutoUpdateRunBusy(false);
    }
  }

  async function handleCleanupCompleted() {
    if (cleanupCount === 0) {
      setNotice("没有可清理的已完成任务");
      return;
    }
    const ok = window.confirm(
      `删除 ${cleanupCount} 个已完成/失败/已取消任务及其输出文件？运行中和排队任务不会受影响。`,
    );
    if (!ok) {
      return;
    }
    setCleanupBusy(true);
    setNotice("");
    try {
      const response = await cleanupCompletedJobs();
      applyJobsSnapshot(response.jobs);
      setNotice(`已清理 ${response.deleted} 个已完成任务`);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "清理已完成任务失败");
      await refreshJobs().catch(() => undefined);
    } finally {
      setCleanupBusy(false);
    }
  }

  function removeJobFromState(jobId: string) {
    setJobs((current) => {
      const next = current.filter((job) => job.id !== jobId);
      setSelectedJobId((selected) => (selected === jobId ? next[0]?.id ?? null : selected));
      return next;
    });
  }

  function markAction(jobId: string, active: boolean) {
    setActionJobIds((current) => {
      const next = new Set(current);
      if (active) {
        next.add(jobId);
      } else {
        next.delete(jobId);
      }
      return next;
    });
  }

  if (authenticated === null) {
    return <div className="boot">正在连接服务...</div>;
  }

  if (!authenticated) {
    if (runtimeInfo.embedded) {
      return (
        <main className="login-shell">
          <section className="login-panel">
            <div className="brand-mark">
              <ShieldCheck size={30} />
            </div>
            <h1>本地会话初始化失败</h1>
            <p>请重新载入应用以创建新的安全会话。</p>
            <button className="primary-button" onClick={() => window.location.reload()}>
              <RotateCcw size={17} />
              重新载入
            </button>
          </section>
        </main>
      );
    }
    return (
      <main className="login-shell">
        <form className="login-panel" onSubmit={handleLogin}>
          <div className="brand-mark">
            <ShieldCheck size={30} />
          </div>
          <h1>轻小说打包器</h1>
          <p>登录后管理服务器下载队列和 Bark 推送。</p>
          <label>
            管理密码
            <span className="field-icon">
              <KeyRound size={17} />
              <input
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                autoFocus
              />
            </span>
          </label>
          <button className="primary-button" type="submit" disabled={busy}>
            <Play size={17} />
            登录
          </button>
          {notice ? <div className="form-error">{notice}</div> : null}
        </form>
      </main>
    );
  }

  return (
    <main className="app-shell">
      <Topbar
        stats={stats}
        embedded={runtimeInfo.embedded}
        activeView={appView}
        onShowWorkspace={() => setAppView("workspace")}
        onShowSettings={() => {
          setAppView("settings");
          setMobileTab("settings");
        }}
        onLogout={handleLogout}
      />

      <section className="desktop-surface" aria-label="轻小说打包器桌面工作区">
        {appView === "settings" ? (
          <SettingsView
            request={request}
            jobs={jobs}
            webDavConfig={webDavConfig}
            webDavBusy={webDavBusy}
            webDavNotice={webDavNotice}
            autoCleanupConfig={autoCleanupConfig}
            autoCleanupBusy={autoCleanupBusy}
            autoCleanupNotice={autoCleanupNotice}
            autoUpdateConfig={autoUpdateConfig}
            autoUpdateBusy={autoUpdateBusy}
            autoUpdateRunBusy={autoUpdateRunBusy}
            autoUpdateNotice={autoUpdateNotice}
            onRequestChange={setRequest}
            onWebDavChange={setWebDavConfig}
            onWebDavSave={() => void handleSaveWebDavConfig(false)}
            onWebDavClearPassword={() => void handleSaveWebDavConfig(true)}
            onWebDavTest={() => void handleTestWebDavConfig()}
            onCleanupChange={setAutoCleanupConfig}
            onCleanupSave={() => void handleSaveCleanupConfig()}
            onAutoUpdateChange={setAutoUpdateConfig}
            onAutoUpdateSave={() => void handleSaveAutoUpdateConfig()}
            onAutoUpdateRunNow={() => void handleRunAutoUpdateNow()}
          />
        ) : (
          <WorkspaceView
            embedded={runtimeInfo.embedded}
            request={request}
            busy={busy}
            previewBusy={previewBusy}
            notice={notice}
            previewState={previewState}
            previewMatchesForm={previewMatchesForm}
            selectedPreviewIds={selectedPreviewIds}
            selectedPreviewCount={selectedPreviews.length}
            previewSelectionEmpty={previewSelectionEmpty}
            usingPreviewIds={currentPreviewAvailable && selectedPreviews.length > 0}
            jobs={jobs}
            stats={stats}
            selectedJob={selectedJob}
            realtimeState={realtimeState}
            actionJobIds={actionJobIds}
            cleanupBusy={cleanupBusy}
            cleanupCount={cleanupCount}
            webDavEnabled={webDavConfig.enabled}
            onRequestChange={setRequest}
            onPreviewSelectionChange={handlePreviewSelection}
            onSelectAllPreviews={handleSelectAllPreviews}
            onClearPreviewSelection={handleClearPreviewSelection}
            onPreview={handlePreview}
            onSubmit={handleSubmit}
            onRefresh={refreshJobs}
            onCleanupCompleted={handleCleanupCompleted}
            onSelectJob={handleSelectJob}
            onCancel={handleCancel}
            onRetry={handleRetry}
            onDelete={handleDelete}
            onDeleteOutputs={handleDeleteOutputs}
          />
        )}
      </section>

      <section className="mobile-surface" aria-label="轻小说打包器手机工作区">
        <MobileTabPanel
          activeTab={mobileTab}
          embedded={runtimeInfo.embedded}
          request={request}
          busy={busy}
          previewBusy={previewBusy}
          notice={notice}
          previewState={previewState}
          previewMatchesForm={previewMatchesForm}
          selectedPreviewIds={selectedPreviewIds}
          selectedPreviewCount={selectedPreviews.length}
          previewSelectionEmpty={previewSelectionEmpty}
          usingPreviewIds={currentPreviewAvailable && selectedPreviews.length > 0}
          jobs={jobs}
          stats={stats}
          selectedJob={selectedJob}
          realtimeState={realtimeState}
          actionJobIds={actionJobIds}
          cleanupBusy={cleanupBusy}
          cleanupCount={cleanupCount}
          webDavConfig={webDavConfig}
          webDavEnabled={webDavConfig.enabled}
          webDavBusy={webDavBusy}
          webDavNotice={webDavNotice}
          autoCleanupConfig={autoCleanupConfig}
          autoCleanupBusy={autoCleanupBusy}
          autoCleanupNotice={autoCleanupNotice}
          autoUpdateConfig={autoUpdateConfig}
          autoUpdateBusy={autoUpdateBusy}
          autoUpdateRunBusy={autoUpdateRunBusy}
          autoUpdateNotice={autoUpdateNotice}
          onRequestChange={setRequest}
          onPreviewSelectionChange={handlePreviewSelection}
          onSelectAllPreviews={handleSelectAllPreviews}
          onClearPreviewSelection={handleClearPreviewSelection}
          onPreview={handlePreview}
          onSubmit={handleSubmit}
          onRefresh={refreshJobs}
          onCleanupCompleted={handleCleanupCompleted}
          onSelectJob={handleSelectJob}
          onCancel={handleCancel}
          onRetry={handleRetry}
          onDelete={handleDelete}
          onDeleteOutputs={handleDeleteOutputs}
          onWebDavChange={setWebDavConfig}
          onWebDavSave={() => void handleSaveWebDavConfig(false)}
          onWebDavClearPassword={() => void handleSaveWebDavConfig(true)}
          onWebDavTest={() => void handleTestWebDavConfig()}
          onCleanupChange={setAutoCleanupConfig}
          onCleanupSave={() => void handleSaveCleanupConfig()}
          onAutoUpdateChange={setAutoUpdateConfig}
          onAutoUpdateSave={() => void handleSaveAutoUpdateConfig()}
          onAutoUpdateRunNow={() => void handleRunAutoUpdateNow()}
        />
      </section>

      <MobileTabBar activeTab={mobileTab} onChange={setMobileTab} />
    </main>
  );
}

function Topbar({
  stats,
  embedded,
  activeView,
  onShowWorkspace,
  onShowSettings,
  onLogout,
}: {
  stats: JobStats;
  embedded: boolean;
  activeView: AppView;
  onShowWorkspace: () => void;
  onShowSettings: () => void;
  onLogout: () => void;
}) {
  return (
    <header className="topbar">
      <div className="topbar-title">
        <div className="brand-mark compact">
          <Server size={22} />
        </div>
        <div>
          <h1>轻小说打包器</h1>
          <p>服务器任务控制台</p>
        </div>
      </div>
      <div className="topbar-actions">
        <StatusMetric icon={<Server size={16} />} label="任务" value={stats.total} />
        <StatusMetric icon={<Loader2 size={16} />} label="运行" value={stats.running} />
        <StatusMetric icon={<Clock3 size={16} />} label="队列" value={stats.queued} />
        <button
          className={`ghost-button topbar-tab ${activeView === "workspace" ? "active" : ""}`}
          onClick={onShowWorkspace}
        >
          <ListOrdered size={17} />
          工作台
        </button>
        <button
          className={`ghost-button topbar-tab ${activeView === "settings" ? "active" : ""}`}
          onClick={onShowSettings}
        >
          <Settings size={17} />
          设置
        </button>
        {!embedded ? (
          <button className="ghost-button" onClick={onLogout}>
            <LogOut size={17} />
            退出
          </button>
        ) : null}
      </div>
    </header>
  );
}

type WorkspaceViewProps = {
  embedded: boolean;
  request: JobRequest;
  busy: boolean;
  previewBusy: boolean;
  notice: string;
  previewState: PreviewState | null;
  previewMatchesForm: boolean;
  selectedPreviewIds: Set<number>;
  selectedPreviewCount: number;
  previewSelectionEmpty: boolean;
  usingPreviewIds: boolean;
  jobs: DownloadJob[];
  stats: JobStats;
  selectedJob?: DownloadJob;
  realtimeState: RealtimeState;
  actionJobIds: Set<string>;
  cleanupBusy: boolean;
  cleanupCount: number;
  webDavEnabled: boolean;
  onRequestChange: (next: JobRequest) => void;
  onPreviewSelectionChange: (sourceId: number, selected: boolean) => void;
  onSelectAllPreviews: () => void;
  onClearPreviewSelection: () => void;
  onPreview: () => void;
  onSubmit: (event: FormEvent) => void;
  onRefresh: () => Promise<void>;
  onCleanupCompleted: () => Promise<void>;
  onSelectJob: (jobId: string) => void;
  onCancel: (job: DownloadJob) => Promise<void>;
  onRetry: (job: DownloadJob) => Promise<void>;
  onDelete: (job: DownloadJob) => Promise<void>;
  onDeleteOutputs: (job: DownloadJob) => Promise<void>;
};

function WorkspaceView({
  embedded,
  request,
  busy,
  previewBusy,
  notice,
  previewState,
  previewMatchesForm,
  selectedPreviewIds,
  selectedPreviewCount,
  previewSelectionEmpty,
  usingPreviewIds,
  jobs,
  stats,
  selectedJob,
  realtimeState,
  actionJobIds,
  cleanupBusy,
  cleanupCount,
  webDavEnabled,
  onRequestChange,
  onPreviewSelectionChange,
  onSelectAllPreviews,
  onClearPreviewSelection,
  onPreview,
  onSubmit,
  onRefresh,
  onCleanupCompleted,
  onSelectJob,
  onCancel,
  onRetry,
  onDelete,
  onDeleteOutputs,
}: WorkspaceViewProps) {
  return (
    <section className="workspace" aria-label="轻小说打包控制台">
      <CreatePanel
        request={request}
        busy={busy}
        previewBusy={previewBusy}
        notice={notice}
        previewState={previewState}
        previewMatchesForm={previewMatchesForm}
        selectedPreviewIds={selectedPreviewIds}
        selectedPreviewCount={selectedPreviewCount}
        previewSelectionEmpty={previewSelectionEmpty}
        usingPreviewIds={usingPreviewIds}
        onRequestChange={onRequestChange}
        onPreviewSelectionChange={onPreviewSelectionChange}
        onSelectAllPreviews={onSelectAllPreviews}
        onClearPreviewSelection={onClearPreviewSelection}
        onPreview={onPreview}
        onSubmit={onSubmit}
      />

      <QueuePanel
        jobs={jobs}
        stats={stats}
        selectedJobId={selectedJob?.id ?? null}
        realtimeState={realtimeState}
        actionJobIds={actionJobIds}
        cleanupBusy={cleanupBusy}
        cleanupCount={cleanupCount}
        webDavEnabled={webDavEnabled}
        onRefresh={onRefresh}
        onCleanupCompleted={onCleanupCompleted}
        onSelect={onSelectJob}
        onCancel={onCancel}
        onRetry={onRetry}
        onDelete={onDelete}
      />

      <JobDetail
        job={selectedJob}
        embedded={embedded}
        busy={selectedJob ? actionJobIds.has(selectedJob.id) : false}
        webDavEnabled={webDavEnabled}
        onDeleteOutputs={onDeleteOutputs}
      />
    </section>
  );
}

type SettingsViewProps = {
  request: JobRequest;
  jobs: DownloadJob[];
  webDavConfig: WebDavConfig;
  webDavBusy: boolean;
  webDavNotice: string;
  autoCleanupConfig: CleanupConfig;
  autoCleanupBusy: boolean;
  autoCleanupNotice: string;
  autoUpdateConfig: AutoUpdateConfig;
  autoUpdateBusy: boolean;
  autoUpdateRunBusy: boolean;
  autoUpdateNotice: string;
  onRequestChange: (next: JobRequest) => void;
  onWebDavChange: (next: WebDavConfig) => void;
  onWebDavSave: () => void;
  onWebDavClearPassword: () => void;
  onWebDavTest: () => void;
  onCleanupChange: (next: CleanupConfig) => void;
  onCleanupSave: () => void;
  onAutoUpdateChange: (next: AutoUpdateConfig) => void;
  onAutoUpdateSave: () => void;
  onAutoUpdateRunNow: () => void;
};

function SettingsView({
  request,
  jobs,
  webDavConfig,
  webDavBusy,
  webDavNotice,
  autoCleanupConfig,
  autoCleanupBusy,
  autoCleanupNotice,
  autoUpdateConfig,
  autoUpdateBusy,
  autoUpdateRunBusy,
  autoUpdateNotice,
  onRequestChange,
  onWebDavChange,
  onWebDavSave,
  onWebDavClearPassword,
  onWebDavTest,
  onCleanupChange,
  onCleanupSave,
  onAutoUpdateChange,
  onAutoUpdateSave,
  onAutoUpdateRunNow,
}: SettingsViewProps) {
  return (
    <section className="settings-page" aria-label="设置">
      <div className="settings-hero">
        <div>
          <h2>设置</h2>
          <p>集中管理 Bark 通知和 WebDAV 上传，主工作台只保留下载、队列和任务详情。</p>
        </div>
      </div>
      <div className="settings-grid">
        <div className="settings-column settings-primary">
          <BarkPanel request={request} onChange={onRequestChange} />
          <AutoUpdatePanel
            config={autoUpdateConfig}
            jobs={jobs}
            busy={autoUpdateBusy}
            runBusy={autoUpdateRunBusy}
            notice={autoUpdateNotice}
            onChange={onAutoUpdateChange}
            onSave={onAutoUpdateSave}
            onRunNow={onAutoUpdateRunNow}
          />
          <AutoCleanupPanel
            config={autoCleanupConfig}
            busy={autoCleanupBusy}
            notice={autoCleanupNotice}
            onChange={onCleanupChange}
            onSave={onCleanupSave}
          />
        </div>
        <div className="settings-column settings-secondary">
          <WebDavPanel
            config={webDavConfig}
            busy={webDavBusy}
            notice={webDavNotice}
            onChange={onWebDavChange}
            onSave={onWebDavSave}
            onClearPassword={onWebDavClearPassword}
            onTest={onWebDavTest}
          />
        </div>
      </div>
    </section>
  );
}

type MobileTabPanelProps = WorkspaceViewProps &
  SettingsViewProps & {
    activeTab: MobileTab;
  };

function MobileTabPanel({
  activeTab,
  ...props
}: MobileTabPanelProps) {
  if (activeTab === "settings") {
    return (
      <SettingsView
        request={props.request}
        jobs={props.jobs}
        webDavConfig={props.webDavConfig}
        webDavBusy={props.webDavBusy}
        webDavNotice={props.webDavNotice}
        autoCleanupConfig={props.autoCleanupConfig}
        autoCleanupBusy={props.autoCleanupBusy}
        autoCleanupNotice={props.autoCleanupNotice}
        autoUpdateConfig={props.autoUpdateConfig}
        autoUpdateBusy={props.autoUpdateBusy}
        autoUpdateRunBusy={props.autoUpdateRunBusy}
        autoUpdateNotice={props.autoUpdateNotice}
        onRequestChange={props.onRequestChange}
        onWebDavChange={props.onWebDavChange}
        onWebDavSave={props.onWebDavSave}
        onWebDavClearPassword={props.onWebDavClearPassword}
        onWebDavTest={props.onWebDavTest}
        onCleanupChange={props.onCleanupChange}
        onCleanupSave={props.onCleanupSave}
        onAutoUpdateChange={props.onAutoUpdateChange}
        onAutoUpdateSave={props.onAutoUpdateSave}
        onAutoUpdateRunNow={props.onAutoUpdateRunNow}
      />
    );
  }

  if (activeTab === "jobs") {
    return (
      <QueuePanel
        jobs={props.jobs}
        stats={props.stats}
        selectedJobId={props.selectedJob?.id ?? null}
        realtimeState={props.realtimeState}
        actionJobIds={props.actionJobIds}
        cleanupBusy={props.cleanupBusy}
        cleanupCount={props.cleanupCount}
        webDavEnabled={props.webDavEnabled}
        onRefresh={props.onRefresh}
        onCleanupCompleted={props.onCleanupCompleted}
        onSelect={props.onSelectJob}
        onCancel={props.onCancel}
        onRetry={props.onRetry}
        onDelete={props.onDelete}
      />
    );
  }

  if (activeTab === "detail") {
    return (
      <JobDetail
        job={props.selectedJob}
        embedded={props.embedded}
        busy={props.selectedJob ? props.actionJobIds.has(props.selectedJob.id) : false}
        webDavEnabled={props.webDavEnabled}
        onDeleteOutputs={props.onDeleteOutputs}
      />
    );
  }

  return (
    <CreatePanel
      request={props.request}
      busy={props.busy}
      previewBusy={props.previewBusy}
      notice={props.notice}
      previewState={props.previewState}
      previewMatchesForm={props.previewMatchesForm}
      selectedPreviewIds={props.selectedPreviewIds}
      selectedPreviewCount={props.selectedPreviewCount}
      previewSelectionEmpty={props.previewSelectionEmpty}
      usingPreviewIds={props.usingPreviewIds}
      onRequestChange={props.onRequestChange}
      onPreviewSelectionChange={props.onPreviewSelectionChange}
      onSelectAllPreviews={props.onSelectAllPreviews}
      onClearPreviewSelection={props.onClearPreviewSelection}
      onPreview={props.onPreview}
      onSubmit={props.onSubmit}
    />
  );
}

function MobileTabBar({
  activeTab,
  onChange,
}: {
  activeTab: MobileTab;
  onChange: (tab: MobileTab) => void;
}) {
  const items: Array<{ tab: MobileTab; label: string; icon: ReactNode }> = [
    { tab: "download", label: "下载", icon: <Download size={18} /> },
    { tab: "jobs", label: "任务", icon: <ListOrdered size={18} /> },
    { tab: "detail", label: "详情", icon: <FileText size={18} /> },
    { tab: "settings", label: "设置", icon: <Settings size={18} /> },
  ];

  return (
    <nav className="mobile-tabbar" aria-label="手机导航">
      {items.map((item) => (
        <button
          key={item.tab}
          type="button"
          className={activeTab === item.tab ? "active" : ""}
          onClick={() => onChange(item.tab)}
        >
          {item.icon}
          <span>{item.label}</span>
        </button>
      ))}
    </nav>
  );
}

function CreatePanel({
  request,
  busy,
  previewBusy,
  notice,
  previewState,
  previewMatchesForm,
  selectedPreviewIds,
  selectedPreviewCount,
  previewSelectionEmpty,
  usingPreviewIds,
  onRequestChange,
  onPreviewSelectionChange,
  onSelectAllPreviews,
  onClearPreviewSelection,
  onPreview,
  onSubmit,
}: {
  request: JobRequest;
  busy: boolean;
  previewBusy: boolean;
  notice: string;
  previewState: PreviewState | null;
  previewMatchesForm: boolean;
  selectedPreviewIds: Set<number>;
  selectedPreviewCount: number;
  previewSelectionEmpty: boolean;
  usingPreviewIds: boolean;
  onRequestChange: (next: JobRequest) => void;
  onPreviewSelectionChange: (sourceId: number, selected: boolean) => void;
  onSelectAllPreviews: () => void;
  onClearPreviewSelection: () => void;
  onPreview: () => void;
  onSubmit: (event: FormEvent) => void;
}) {
  return (
    <form className="panel create-panel" onSubmit={onSubmit}>
      <PanelHeader
        title="新建下载"
        description="先搜索确认可用 ID，再把有效结果加入队列。"
        actions={
          <div className="create-actions">
            <button
              className="ghost-button"
              type="button"
              disabled={previewBusy}
              onClick={onPreview}
            >
              {previewBusy ? <Loader2 className="spin-icon" size={17} /> : <Search size={17} />}
              搜索
            </button>
            <button
              className="primary-button"
              type="submit"
              disabled={busy || previewSelectionEmpty}
            >
              <Play size={17} />
              {previewSelectionEmpty
                ? "请先勾选"
                : usingPreviewIds
                  ? "下载勾选结果"
                  : "开始下载"}
            </button>
          </div>
        }
      />

      <div className="create-body">
        <div className="create-fixed">
        <label className="wide-field">
          URL 模板
          <input
            value={request.urlTemplate}
            onChange={(event) =>
              onRequestChange({ ...request, urlTemplate: event.target.value })
            }
            placeholder="https://www.bilinovel.com/novel/{id}.html"
          />
        </label>

        <div className="form-grid">
          <label>
            小说 ID 范围
            <span className="field-icon">
              <ListOrdered size={17} />
              <input
                value={request.rangeText}
                onChange={(event) =>
                  onRequestChange({ ...request, rangeText: event.target.value })
                }
                placeholder="1,2,3 或 1-5,7"
              />
            </span>
            <span className="field-hint">填单个 ID 即可下载一本；也支持 1,2,3 / 1-5,7 / 7~9，重复 ID 会自动去重。</span>
          </label>
          <label>
            分卷范围
            <input
              value={request.volumeRangeText}
              onChange={(event) =>
                onRequestChange({ ...request, volumeRangeText: event.target.value })
              }
              placeholder="留空为全部，也可填 1,2,3 或 1-5,7"
            />
            <span className="field-hint">留空或 0 表示全部；可用逗号和范围混写。</span>
          </label>
        </div>

        <div className="switch-row">
          <Toggle
            label="合并分卷"
            checked={request.combineVolume}
            onChange={(checked) => onRequestChange({ ...request, combineVolume: checked })}
          />
          <Toggle
            label="章节标题"
            checked={request.addChapterTitle}
            onChange={(checked) =>
              onRequestChange({ ...request, addChapterTitle: checked })
            }
          />
        </div>

        {notice ? <div className="notice">{notice}</div> : null}
      </div>

      <div className="create-results-scroll">
        <SearchResults
          state={previewState}
          activeRequest={request}
          isCurrent={previewMatchesForm}
          selectedPreviewIds={selectedPreviewIds}
          selectedPreviewCount={selectedPreviewCount}
          onPreviewSelectionChange={onPreviewSelectionChange}
          onSelectAllPreviews={onSelectAllPreviews}
          onClearPreviewSelection={onClearPreviewSelection}
        />
      </div>
      </div>
    </form>
  );
}

function QueuePanel({
  jobs,
  stats,
  selectedJobId,
  realtimeState,
  actionJobIds,
  cleanupBusy,
  cleanupCount,
  webDavEnabled,
  onRefresh,
  onCleanupCompleted,
  onSelect,
  onCancel,
  onRetry,
  onDelete,
}: {
  jobs: DownloadJob[];
  stats: JobStats;
  selectedJobId: string | null;
  realtimeState: RealtimeState;
  actionJobIds: Set<string>;
  cleanupBusy: boolean;
  cleanupCount: number;
  webDavEnabled: boolean;
  onRefresh: () => Promise<void>;
  onCleanupCompleted: () => Promise<void>;
  onSelect: (jobId: string) => void;
  onCancel: (job: DownloadJob) => Promise<void>;
  onRetry: (job: DownloadJob) => Promise<void>;
  onDelete: (job: DownloadJob) => Promise<void>;
}) {
  return (
    <section className="panel queue-panel">
      <PanelHeader
        title="任务队列"
        description={`${stats.done} 完成 · ${stats.failed} 失败`}
        actions={
          <div className="heading-actions">
            <RealtimeBadge state={realtimeState} />
            <button
              className="ghost-button"
              disabled={cleanupBusy || cleanupCount === 0}
              onClick={() => void onCleanupCompleted()}
            >
              {cleanupBusy ? <Loader2 className="spin-icon" size={16} /> : <Trash2 size={16} />}
              清理完成
            </button>
            <button className="ghost-button" onClick={() => void onRefresh()}>
              <RotateCcw size={16} />
              刷新
            </button>
          </div>
        }
      />

      <div className="queue-scroll">
        <div className="queue-table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>小说</th>
                <th>状态</th>
              <th>进度</th>
              <th>Bark</th>
              <th>WebDAV</th>
              <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {jobs.map((job) => (
                <JobRow
                  key={job.id}
                  job={job}
                  busy={actionJobIds.has(job.id)}
                  selected={selectedJobId === job.id}
                  webDavEnabled={webDavEnabled}
                  onSelect={() => onSelect(job.id)}
                  onCancel={() => onCancel(job)}
                  onRetry={() => onRetry(job)}
                  onDelete={() => onDelete(job)}
                />
              ))}
            </tbody>
          </table>
        </div>
        <div className="job-card-list">
          {jobs.map((job) => (
            <JobCard
              key={job.id}
              job={job}
              busy={actionJobIds.has(job.id)}
              selected={selectedJobId === job.id}
              webDavEnabled={webDavEnabled}
              onSelect={() => onSelect(job.id)}
              onCancel={() => onCancel(job)}
              onRetry={() => onRetry(job)}
              onDelete={() => onDelete(job)}
            />
          ))}
        </div>
        {jobs.length === 0 ? <div className="empty-state">暂无任务</div> : null}
      </div>
    </section>
  );
}

function BarkPanel({
  request,
  onChange,
}: {
  request: JobRequest;
  onChange: (next: JobRequest) => void;
}) {
  const bark = request.barkConfig;
  const updateBark = (next: Partial<BarkConfig>) =>
    onChange({ ...request, barkConfig: { ...bark, ...next } });

  return (
    <section className="panel bark-settings-panel">
      <PanelHeader
        title="Bark 通知"
        icon={<Bell size={17} />}
        actions={
          <Toggle
            label="启用"
            checked={bark.enabled}
            onChange={(checked) => updateBark({ enabled: checked })}
          />
        }
      />
      <div className="bark-body">
        <label>
          服务地址
          <input
            value={bark.serverUrl}
            onChange={(event) => updateBark({ serverUrl: event.target.value })}
          />
        </label>
        <label>
          Device Key
          <input
            value={bark.deviceKey}
            onChange={(event) => updateBark({ deviceKey: event.target.value })}
            placeholder="留空则不发送"
          />
        </label>
        <div className="switch-row compact">
          {(["start", "success", "failure", "progress", "update"] as const).map((key) => (
            <Toggle
              key={key}
              label={eventLabel[key]}
              checked={bark.events[key]}
              onChange={(checked) =>
                updateBark({ events: { ...bark.events, [key]: checked } })
              }
            />
          ))}
        </div>
      </div>
    </section>
  );
}

function AutoCleanupPanel({
  config,
  busy,
  notice,
  onChange,
  onSave,
}: {
  config: CleanupConfig;
  busy: boolean;
  notice: string;
  onChange: (next: CleanupConfig) => void;
  onSave: () => void;
}) {
  const updateConfig = (next: Partial<CleanupConfig>) =>
    onChange({ ...config, ...next });

  return (
    <section className="panel auto-cleanup-settings-panel">
      <PanelHeader
        title="自动清理"
        icon={<Trash2 size={17} />}
        actions={
          <Toggle
            label="启用"
            checked={config.enabled}
            onChange={(checked) => updateConfig({ enabled: checked })}
          />
        }
      />
      <div className="cleanup-body">
        <label>
          保留天数
          <input
            type="number"
            min={1}
            max={365}
            step={1}
            value={config.retentionDays}
            onChange={(event) =>
              updateConfig({ retentionDays: Number(event.target.value) })
            }
          />
        </label>
        <button className="primary-button compact" type="button" disabled={busy} onClick={onSave}>
          {busy ? <Loader2 className="spin-icon" size={16} /> : <Save size={16} />}
          保存
        </button>
        {notice ? <div className="inline-notice">{notice}</div> : null}
      </div>
    </section>
  );
}

function AutoUpdatePanel({
  config,
  jobs,
  busy,
  runBusy,
  notice,
  onChange,
  onSave,
  onRunNow,
}: {
  config: AutoUpdateConfig;
  jobs: DownloadJob[];
  busy: boolean;
  runBusy: boolean;
  notice: string;
  onChange: (next: AutoUpdateConfig) => void;
  onSave: () => void;
  onRunNow: () => void;
}) {
  const successfulJobs = useMemo(
    () => jobs.filter((job) => job.status === "succeeded"),
    [jobs],
  );
  const itemsByJobId = useMemo(
    () => new Map(config.items.map((item) => [item.jobId, item])),
    [config.items],
  );
  const successfulJobIds = useMemo(
    () => new Set(successfulJobs.map((job) => job.id)),
    [successfulJobs],
  );
  const selectedCount = config.items.filter(
    (item) => item.enabled !== false && successfulJobIds.has(item.jobId),
  ).length;
  const updateConfig = (next: Partial<AutoUpdateConfig>) =>
    onChange({ ...config, ...next });

  function toggleJob(job: DownloadJob, selected: boolean) {
    if (selected) {
      const current = itemsByJobId.get(job.id);
      const nextItem: AutoUpdateItem = {
        ...current,
        jobId: job.id,
        enabled: true,
      };
      onChange({
        ...config,
        items: upsertAutoUpdateItem(config.items, nextItem),
      });
      return;
    }
    onChange({
      ...config,
      items: config.items.filter((item) => item.jobId !== job.id),
    });
  }

  return (
    <section className="panel auto-update-settings-panel">
      <PanelHeader
        title="自动更新"
        icon={<Clock3 size={17} />}
        actions={
          <Toggle
            label="启用"
            checked={config.enabled}
            onChange={(checked) => updateConfig({ enabled: checked })}
          />
        }
      />
      <div className="auto-update-body">
        <div className="auto-update-toolbar">
          <label className="auto-update-time">
            每日时间
            <input
              type="time"
              value={config.dailyTime}
              onChange={(event) => updateConfig({ dailyTime: event.target.value })}
            />
          </label>
          <div className="auto-update-actions">
            <button
              className="primary-button compact"
              type="button"
              disabled={busy}
              onClick={onSave}
            >
              {busy ? <Loader2 className="spin-icon" size={16} /> : <Save size={16} />}
              保存
            </button>
            <button
              className="ghost-button"
              type="button"
              disabled={runBusy || selectedCount === 0}
              onClick={onRunNow}
            >
              {runBusy ? <Loader2 className="spin-icon" size={16} /> : <Play size={16} />}
              立即检查
            </button>
          </div>
        </div>
        <div className="auto-update-meta">
          <span>已选 {selectedCount} 本</span>
          <span>上次自动：{config.lastRunAt ? formatDateTime(config.lastRunAt) : "尚未运行"}</span>
        </div>
        <div className="auto-update-job-list">
          {successfulJobs.map((job) => {
            const item = itemsByJobId.get(job.id);
            const selected = item?.enabled !== false && item !== undefined;
            const hints = autoUpdateHints(job);
            return (
              <label
                key={job.id}
                className={`auto-update-job ${selected ? "selected" : ""}`}
              >
                <input
                  type="checkbox"
                  checked={selected}
                  onChange={(event) => toggleJob(job, event.target.checked)}
                />
                <span className="auto-update-check" />
                <div className="auto-update-job-main">
                  <strong title={job.title ?? job.url}>
                    #{job.sourceId} {job.title ?? "未命名任务"}
                  </strong>
                  <p>{autoUpdateItemStatus(item)}</p>
                  {hints.length > 0 ? (
                    <div className="auto-update-hints">
                      {hints.map((hint) => (
                        <span key={hint}>{hint}</span>
                      ))}
                    </div>
                  ) : null}
                </div>
              </label>
            );
          })}
          {successfulJobs.length === 0 ? (
            <div className="empty-state compact">暂无可追更的成功任务</div>
          ) : null}
        </div>
        {notice ? <div className="inline-notice">{notice}</div> : null}
      </div>
    </section>
  );
}

function WebDavPanel({
  config,
  busy,
  notice,
  onChange,
  onSave,
  onClearPassword,
  onTest,
}: {
  config: WebDavConfig;
  busy: boolean;
  notice: string;
  onChange: (next: WebDavConfig) => void;
  onSave: () => void;
  onClearPassword: () => void;
  onTest: () => void;
}) {
  const updateConfig = (next: Partial<WebDavConfig>) =>
    onChange({ ...config, ...next });

  return (
    <section className="panel webdav-settings-panel">
      <PanelHeader
        title="WebDAV 上传"
        icon={<CloudUpload size={17} />}
        actions={
          <Toggle
            label="启用"
            checked={config.enabled}
            onChange={(checked) => updateConfig({ enabled: checked })}
          />
        }
      />
      <div className="webdav-body">
        <label>
          服务地址
          <input
            value={config.serverUrl}
            onChange={(event) => updateConfig({ serverUrl: event.target.value })}
            placeholder="https://example.com/dav/"
          />
        </label>
        <label>
          用户名
          <input
            value={config.username}
            onChange={(event) => updateConfig({ username: event.target.value })}
          />
        </label>
        <label>
          密码
          <input
            type="password"
            value={config.password ?? ""}
            onChange={(event) => updateConfig({ password: event.target.value })}
            placeholder={config.hasPassword ? "留空不修改已保存密码" : "请输入 WebDAV 密码"}
          />
        </label>
        <label>
          基础目录
          <input
            value={config.basePath}
            onChange={(event) => updateConfig({ basePath: event.target.value })}
            placeholder="/小说/轻小说打包器"
          />
        </label>
        <div className="webdav-actions">
          <button className="ghost-button" type="button" disabled={busy} onClick={onTest}>
            {busy ? <Loader2 className="spin-icon" size={16} /> : <CloudUpload size={16} />}
            测试连接
          </button>
          <button className="primary-button compact" type="button" disabled={busy} onClick={onSave}>
            {busy ? <Loader2 className="spin-icon" size={16} /> : <Save size={16} />}
            保存
          </button>
        </div>
        {config.hasPassword ? (
          <button
            className="text-button"
            type="button"
            disabled={busy}
            onClick={onClearPassword}
          >
            清空已保存密码
          </button>
        ) : null}
        {notice ? <div className="inline-notice">{notice}</div> : null}
      </div>
    </section>
  );
}

function JobDetail({
  job,
  embedded,
  busy,
  webDavEnabled,
  onDeleteOutputs,
}: {
  job?: DownloadJob;
  embedded: boolean;
  busy: boolean;
  webDavEnabled: boolean;
  onDeleteOutputs: (job: DownloadJob) => Promise<void>;
}) {
  if (!job) {
    return (
      <section className="panel detail-panel">
        <PanelHeader title="任务详情" description="任务运行时会显示章节进度。" />
        <div className="empty-state">暂无任务</div>
      </section>
    );
  }

  const progress = Math.max(0, Math.min(100, Math.round(job.progress * 100)));
  const canDeleteOutputs = isCleanupTarget(job) && job.outputFiles.length > 0;
  const outputDir = job.outputDir ?? `outputs/${job.id}`;

  return (
    <section className="panel detail-panel">
      <PanelHeader
        title="任务详情"
        description={job.message}
        actions={<StatusBadge status={job.status} />}
      />
      <div className="detail-fixed">
        <div className="detail-summary">
          <span>当前任务</span>
          <strong>{job.title ?? `#${job.sourceId}`}</strong>
          <p>{job.author ?? job.url}</p>
          <div className="progress-cell wide">
            <div className="progress-bar">
              <span style={{ width: `${progress}%` }} />
            </div>
            <em>{progress}%</em>
          </div>
        </div>

        <div className="detail-grid">
          <div>
            <span>来源</span>
            <strong>{job.sourceName ?? "待识别"}</strong>
          </div>
          <div>
            <span>分卷</span>
            <strong>{job.volumeSummary ?? "待加载"}</strong>
          </div>
        </div>

        <div className="storage-card">
          <div>
            <span>保存位置</span>
            <strong title={outputDir}>{outputDir}</strong>
            <p>
              {embedded
                ? "文件保存在 App 沙箱；长任务请保持应用在前台，完成后点文件名分享到“文件”或阅读器。"
                : `Docker 本地默认映射到 ./data/outputs/${job.id}`}
            </p>
          </div>
          <button
            className="ghost-button"
            type="button"
            disabled={busy || !canDeleteOutputs}
            onClick={() => void onDeleteOutputs(job)}
            title={canDeleteOutputs ? "删除输出文件，保留任务记录" : "暂无可清理输出"}
          >
            {busy ? <Loader2 className="spin-icon" size={16} /> : <Trash2 size={16} />}
            清理输出
          </button>
        </div>

        {job.outputFiles.length > 0 ? (
          <div className="file-list stacked">
            {job.outputFiles.map((file) => (
              <a key={file} href={fileUrl(job.id, file)} title={file}>
                <Download size={16} />
                <span>{file}</span>
              </a>
            ))}
          </div>
        ) : (
          <div className="file-empty">生成 EPUB 后可在这里单独下载每个文件。</div>
        )}

        <UploadSummary job={job} webDavEnabled={webDavEnabled} />
      </div>

        <div className="log-box">
          {job.logs.length === 0 ? "暂无日志" : job.logs.slice(-80).join("\n")}
        </div>
    </section>
  );
}

function UploadSummary({
  job,
  webDavEnabled,
}: {
  job: DownloadJob;
  webDavEnabled: boolean;
}) {
  const upload = getUploadDisplay(job, webDavEnabled);
  const uploadedFiles = job.uploadedFiles ?? [];
  return (
    <div className={`upload-card ${upload.status}`}>
      <div>
        <span>WebDAV</span>
        <strong>{upload.label}</strong>
        {upload.description && !job.uploadError ? <p>{upload.description}</p> : null}
        {job.uploadError ? <p>{job.uploadError}</p> : null}
      </div>
      {uploadedFiles.length > 0 ? (
        <div className="remote-file-list">
          {uploadedFiles.map((file) => (
            <span key={file} title={file}>
              {file}
            </span>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function UploadBadge({
  job,
  webDavEnabled,
}: {
  job: DownloadJob;
  webDavEnabled: boolean;
}) {
  const upload = getUploadDisplay(job, webDavEnabled);
  return <span className={`upload-pill ${upload.status}`}>{upload.label}</span>;
}

function getUploadDisplay(job: DownloadJob, webDavEnabled: boolean): UploadDisplay {
  const status = job.uploadStatus ?? "disabled";
  if (status === "succeeded" || status === "uploading" || status === "failed") {
    return {
      status,
      label: uploadStatusText[status],
    };
  }

  if (status === "pending") {
    return {
      status,
      label: uploadStatusText.pending,
      description: "WebDAV 已启用，生成 EPUB 后会自动上传。",
    };
  }

  if (!webDavEnabled) {
    return {
      status: "disabled",
      label: uploadStatusText.disabled,
      description: "当前 WebDAV 未启用，任务完成后只保留本地 EPUB。",
    };
  }

  if (job.status === "queued" || job.status === "running" || job.status === "canceling") {
    return {
      status: "pending",
      label: uploadStatusText.pending,
      description: "WebDAV 已启用，生成 EPUB 后会自动上传。",
    };
  }

  return {
    status: "not-uploaded",
    label: uploadStatusText["not-uploaded"],
    description:
      job.status === "canceled"
        ? "任务已取消，没有生成可上传的 EPUB。"
        : "这个任务没有上传记录；重试后会按当前 WebDAV 设置上传。",
  };
}

function PanelHeader({
  title,
  description,
  icon,
  actions,
}: {
  title: string;
  description?: string;
  icon?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div className="panel-heading">
      <div className="heading-title">
        {icon ? <span className="heading-icon">{icon}</span> : null}
        <div>
          <h2>{title}</h2>
          {description ? <p>{description}</p> : null}
        </div>
      </div>
      {actions ? <div className="panel-actions">{actions}</div> : null}
    </div>
  );
}

function SearchResults({
  state,
  activeRequest,
  isCurrent,
  selectedPreviewIds,
  selectedPreviewCount,
  onPreviewSelectionChange,
  onSelectAllPreviews,
  onClearPreviewSelection,
}: {
  state: PreviewState | null;
  activeRequest: JobRequest;
  isCurrent: boolean;
  selectedPreviewIds: Set<number>;
  selectedPreviewCount: number;
  onPreviewSelectionChange: (sourceId: number, selected: boolean) => void;
  onSelectAllPreviews: () => void;
  onClearPreviewSelection: () => void;
}) {
  if (!state) {
    return null;
  }

  const skippedCount = state.failures.length;
  const foundIds = state.previews.map((preview) => preview.sourceId).join(", ");
  const expectedRange = activeRequest.rangeText.trim();
  const selectionText = isCurrent
    ? `已选 ${selectedPreviewCount} / ${state.previews.length}`
    : "结果已过期";

  return (
    <section className={`preview-results ${isCurrent ? "" : "stale"}`} aria-label="搜索结果">
      <div className="preview-results-heading">
        <div>
          <h3>搜索结果</h3>
          <span>
            {state.previews.length} 本 · {selectionText}
            {skippedCount > 0 ? ` · 跳过 ${skippedCount} 个` : ""}
          </span>
        </div>
        <div className="preview-heading-actions">
          {isCurrent && state.previews.length > 0 ? (
            <>
              <button type="button" onClick={onSelectAllPreviews}>
                全选
              </button>
              <button type="button" onClick={onClearPreviewSelection}>
                清空
              </button>
              <span className="result-id-list" title={foundIds}>
                {foundIds}
              </span>
            </>
          ) : null}
        </div>
      </div>
      {!isCurrent ? (
        <div className="preview-note">当前输入为 {expectedRange || "空"}，搜索结果已过期。</div>
      ) : null}
      {isCurrent && state.previews.length > 0 && selectedPreviewCount === 0 ? (
        <div className="preview-note">至少勾选一本小说后才能下载搜索结果。</div>
      ) : null}
      <div className="preview-grid">
        {state.previews.map((preview) => (
          <NovelPreviewCard
            key={`${preview.sourceId}-${preview.url}`}
            preview={preview}
            selected={selectedPreviewIds.has(preview.sourceId)}
            disabled={!isCurrent}
            onSelectedChange={(selected) =>
              onPreviewSelectionChange(preview.sourceId, selected)
            }
          />
        ))}
      </div>
    </section>
  );
}

function NovelPreviewCard({
  preview,
  selected,
  disabled,
  onSelectedChange,
}: {
  preview: NovelPreview;
  selected: boolean;
  disabled: boolean;
  onSelectedChange: (selected: boolean) => void;
}) {
  return (
    <div className={`preview-card ${selected ? "selected" : ""}`}>
      <label className="preview-check" title={selected ? "取消选择" : "选择下载"}>
        <input
          type="checkbox"
          checked={selected}
          disabled={disabled}
          onChange={(event) => onSelectedChange(event.target.checked)}
        />
        <span />
      </label>
      {preview.coverUrl ? (
        <img src={preview.coverUrl} alt={preview.title} />
      ) : (
        <div className="preview-cover-empty">无封面</div>
      )}
      <div className="preview-copy">
        <div className="preview-title">
          <strong>{preview.title}</strong>
          <div className="preview-badges">
            <span>#{preview.sourceId}</span>
            <span>{preview.status}</span>
          </div>
        </div>
        <p>
          {preview.alias ? `${preview.alias} · ` : ""}
          {preview.author}
        </p>
        <div className="preview-meta">
          <span>{preview.sourceName}</span>
          {preview.publisher ? <span>{preview.publisher}</span> : null}
          {preview.volumeCount !== undefined ? <span>{preview.volumeCount} 卷</span> : null}
          {preview.chapterCount !== undefined ? <span>{preview.chapterCount} 章</span> : null}
        </div>
        {preview.tags.length > 0 ? (
          <div className="preview-tags">
            {preview.tags.slice(0, 5).map((tag) => (
              <span key={tag}>{tag}</span>
            ))}
          </div>
        ) : null}
        {preview.description ? <p className="preview-desc">{preview.description}</p> : null}
      </div>
    </div>
  );
}

function JobRow({
  job,
  busy,
  selected,
  webDavEnabled,
  onSelect,
  onCancel,
  onRetry,
  onDelete,
}: {
  job: DownloadJob;
  busy: boolean;
  selected: boolean;
  webDavEnabled: boolean;
  onSelect: () => void;
  onCancel: () => Promise<void>;
  onRetry: () => Promise<void>;
  onDelete: () => Promise<void>;
}) {
  const terminal = ["succeeded", "failed", "canceled", "canceling"].includes(job.status);
  const canCancel = !terminal;
  const progress = Math.max(0, Math.min(100, Math.round(job.progress * 100)));

  return (
    <tr className={selected ? "selected-row" : ""} onClick={onSelect}>
      <td className="id-cell">#{job.sourceId}</td>
      <td>
        <strong>{job.title ?? "等待加载"}</strong>
        <span>{job.author ?? job.url}</span>
      </td>
      <td>
        <StatusBadge status={job.status} />
      </td>
      <td>
        <div className="progress-cell" title={job.message}>
          <div className="progress-bar">
            <span style={{ width: `${progress}%` }} />
          </div>
          <em>{progress}%</em>
        </div>
      </td>
      <td>
        <span className={job.request.barkConfig.enabled ? "bark-on" : "bark-off"}>
          {job.request.barkConfig.enabled ? "开" : "关"}
        </span>
      </td>
      <td>
        <UploadBadge job={job} webDavEnabled={webDavEnabled} />
      </td>
      <td>
        <div className="row-actions">
          {!terminal ? (
            <button
              title="取消任务"
              disabled={busy || !canCancel}
              onClick={(event) => runRowAction(event, onCancel)}
            >
              {busy ? (
                <Loader2 className="spin-icon" size={16} />
              ) : (
                <StopCircle size={16} />
              )}
            </button>
          ) : null}
          {job.status === "failed" || job.status === "canceled" ? (
            <button
              title="重试"
              disabled={busy}
              onClick={(event) => runRowAction(event, onRetry)}
            >
              {busy ? <Loader2 className="spin-icon" size={16} /> : <RotateCcw size={16} />}
            </button>
          ) : null}
          {job.outputFiles.length === 1 ? (
            <a title={job.outputFiles[0]} href={fileUrl(job.id, job.outputFiles[0])}>
              <Download size={16} />
            </a>
          ) : null}
          {job.outputFiles.length > 1 ? (
            <button title="在详情中选择文件" onClick={(event) => runRowAction(event, onSelect)}>
              <FileText size={16} />
            </button>
          ) : null}
          <button
            title="删除任务"
            disabled={busy}
            onClick={(event) => runRowAction(event, onDelete)}
          >
            {busy ? <Loader2 className="spin-icon" size={16} /> : <Trash2 size={16} />}
          </button>
        </div>
      </td>
    </tr>
  );
}

function RealtimeBadge({ state }: { state: RealtimeState }) {
  const Icon = state === "offline" ? WifiOff : Wifi;
  return (
    <span className={`sync-badge ${state}`}>
      <Icon size={14} />
      {realtimeText[state]}
    </span>
  );
}

function JobCard({
  job,
  busy,
  selected,
  webDavEnabled,
  onSelect,
  onCancel,
  onRetry,
  onDelete,
}: {
  job: DownloadJob;
  busy: boolean;
  selected: boolean;
  webDavEnabled: boolean;
  onSelect: () => void;
  onCancel: () => Promise<void>;
  onRetry: () => Promise<void>;
  onDelete: () => Promise<void>;
}) {
  const terminal = ["succeeded", "failed", "canceled", "canceling"].includes(job.status);
  const progress = Math.max(0, Math.min(100, Math.round(job.progress * 100)));

  return (
    <article className={`job-card ${selected ? "selected" : ""}`} onClick={onSelect}>
      <div className="job-card-main">
        <span className="id-cell">#{job.sourceId}</span>
        <div>
          <strong>{job.title ?? "等待加载"}</strong>
          <p>{job.author ?? job.url}</p>
        </div>
        <StatusBadge status={job.status} />
      </div>
      <div className="progress-cell wide">
        <div className="progress-bar">
          <span style={{ width: `${progress}%` }} />
        </div>
        <em>{progress}%</em>
      </div>
      <div className="job-card-meta">
        <span className={job.request.barkConfig.enabled ? "bark-on" : "bark-off"}>
          Bark {job.request.barkConfig.enabled ? "开" : "关"}
        </span>
        <UploadBadge job={job} webDavEnabled={webDavEnabled} />
      </div>
      <div className="row-actions">
        {!terminal ? (
          <button
            title="取消任务"
            disabled={busy}
            onClick={(event) => runRowAction(event, onCancel)}
          >
            {busy ? <Loader2 className="spin-icon" size={16} /> : <StopCircle size={16} />}
          </button>
        ) : null}
        {job.status === "failed" || job.status === "canceled" ? (
          <button
            title="重试"
            disabled={busy}
            onClick={(event) => runRowAction(event, onRetry)}
          >
            {busy ? <Loader2 className="spin-icon" size={16} /> : <RotateCcw size={16} />}
          </button>
        ) : null}
        {job.outputFiles.length === 1 ? (
          <a title={job.outputFiles[0]} href={fileUrl(job.id, job.outputFiles[0])} onClick={(event) => event.stopPropagation()}>
            <Download size={16} />
          </a>
        ) : null}
        {job.outputFiles.length > 1 ? (
          <button title="在详情中选择文件" onClick={(event) => runRowAction(event, onSelect)}>
            <FileText size={16} />
          </button>
        ) : null}
        <button
          title="删除任务"
          disabled={busy}
          onClick={(event) => runRowAction(event, onDelete)}
        >
          {busy ? <Loader2 className="spin-icon" size={16} /> : <Trash2 size={16} />}
        </button>
      </div>
    </article>
  );
}

function runRowAction(event: MouseEvent, action: () => void | Promise<void>) {
  event.stopPropagation();
  void action();
}

function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="toggle">
      <input
        type="checkbox"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
      />
      <span />
      {label}
    </label>
  );
}

function StatusMetric({
  icon,
  label,
  value,
}: {
  icon: ReactNode;
  label: string;
  value: number;
}) {
  return (
    <div className="metric">
      {icon}
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function StatusBadge({ status }: { status: JobStatus }) {
  const Icon = statusIcons[status];
  return (
    <span className={`status-badge ${status}`}>
      <Icon className={status === "running" ? "spin-icon" : ""} size={15} />
      {statusText[status]}
    </span>
  );
}

function upsertJob(current: DownloadJob[], incoming: DownloadJob) {
  let found = false;
  const next = current.map((job) => {
    if (job.id !== incoming.id) {
      return job;
    }
    found = true;
    return incoming;
  });
  return found ? next : [incoming, ...current];
}

function isCleanupTarget(job: DownloadJob) {
  return job.status === "succeeded" || job.status === "failed" || job.status === "canceled";
}

function upsertAutoUpdateItem(
  current: AutoUpdateItem[],
  incoming: AutoUpdateItem,
) {
  let found = false;
  const next = current.map((item) => {
    if (item.jobId !== incoming.jobId) {
      return item;
    }
    found = true;
    return incoming;
  });
  return found ? next : [...next, incoming];
}

function autoUpdateHints(job: DownloadJob) {
  const hints: string[] = [];
  if (!job.request.barkConfig.enabled || !job.request.barkConfig.events.update) {
    hints.push("Bark 未启用");
  }
  if (job.webDavConfig?.enabled !== true) {
    hints.push("WebDAV 未启用");
  }
  return hints;
}

function autoUpdateItemStatus(item?: AutoUpdateItem) {
  if (!item) {
    return "未纳入追更";
  }
  const label = item.lastStatus
    ? (autoUpdateStatusText[item.lastStatus] ?? item.lastStatus)
    : item.baselineFingerprint
      ? "等待检查"
      : "待记录基线";
  const checkedAt = item.lastCheckedAt ? ` · ${formatDateTime(item.lastCheckedAt)}` : "";
  const message = item.lastMessage ? ` · ${item.lastMessage}` : "";
  return `${label}${checkedAt}${message}`;
}

function formatDateTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
}

function normalizeTimeInput(value: string) {
  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!match) {
    return defaultAutoUpdateConfig.dailyTime;
  }
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return defaultAutoUpdateConfig.dailyTime;
  }
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function mergeNewJobs(current: DownloadJob[], incoming: DownloadJob[]) {
  const incomingIds = new Set(incoming.map((job) => job.id));
  return [...incoming, ...current.filter((job) => !incomingIds.has(job.id))];
}

function patchJob(
  current: DownloadJob[],
  jobId: string,
  patch: Partial<DownloadJob>,
) {
  return current.map((job) => {
    if (job.id !== jobId) {
      return job;
    }
    const message = patch.message ?? job.message;
    return {
      ...job,
      ...patch,
      logs: patch.message ? appendLocalLog(job.logs, message) : (patch.logs ?? job.logs),
    };
  });
}

function appendLocalLog(logs: string[], message: string) {
  const time = new Date().toLocaleTimeString("zh-CN", { hour12: false });
  return [...logs, `[${time}] ${message}`].slice(-200);
}

function readStoredBarkConfig(): BarkConfig {
  if (typeof window === "undefined") {
    return defaultBark;
  }
  try {
    const raw = window.localStorage.getItem(barkStorageKey);
    if (!raw) {
      return defaultBark;
    }
    const parsed = JSON.parse(raw) as Partial<BarkConfig>;
    return {
      ...defaultBark,
      ...parsed,
      events: {
        ...defaultBark.events,
        ...(parsed.events ?? {}),
      },
      progressThrottleSeconds:
        typeof parsed.progressThrottleSeconds === "number"
          ? parsed.progressThrottleSeconds
          : defaultBark.progressThrottleSeconds,
    };
  } catch {
    return defaultBark;
  }
}

function writeStoredBarkConfig(config: BarkConfig) {
  if (typeof window === "undefined") {
    return;
  }
  try {
    window.localStorage.setItem(barkStorageKey, JSON.stringify(config));
  } catch {
    // Ignore storage errors so private browsing or quota issues do not block the UI.
  }
}

function previewSignature(request: JobRequest) {
  return JSON.stringify({
    urlTemplate: request.urlTemplate.trim(),
    rangeText: request.rangeText.trim(),
  });
}

const eventLabel = {
  start: "开始",
  success: "成功",
  failure: "失败",
  progress: "进度",
  update: "追更",
};

const autoUpdateStatusText: Record<string, string> = {
  baseline: "已记录基线",
  unchanged: "暂无更新",
  updated: "已更新",
  failed: "检查失败",
  missing: "任务丢失",
  skipped: "已跳过",
};

const realtimeText: Record<RealtimeState, string> = {
  connecting: "实时连接中",
  connected: "实时同步",
  offline: "轮询同步",
};

const statusText: Record<JobStatus, string> = {
  queued: "排队",
  running: "运行",
  canceling: "已取消",
  succeeded: "完成",
  failed: "失败",
  canceled: "已取消",
};

const uploadStatusText: Record<UploadDisplayStatus, string> = {
  disabled: "未启用",
  pending: "等待上传",
  uploading: "上传中",
  succeeded: "已上传",
  failed: "上传失败",
  "not-uploaded": "未上传",
};

const statusIcons: Record<JobStatus, LucideIcon> = {
  queued: Clock3,
  running: Loader2,
  canceling: StopCircle,
  succeeded: CheckCircle2,
  failed: XCircle,
  canceled: StopCircle,
};
