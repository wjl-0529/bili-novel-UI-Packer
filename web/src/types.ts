export type JobStatus =
  | "queued"
  | "running"
  | "paused"
  | "canceling"
  | "succeeded"
  | "failed"
  | "canceled";

export type RuntimeInfo = {
  embedded: boolean;
  platform: string | null;
};

export type BarkEvents = {
  start: boolean;
  success: boolean;
  failure: boolean;
  progress: boolean;
  update: boolean;
};

export type BarkConfig = {
  enabled: boolean;
  serverUrl: string;
  deviceKey: string;
  events: BarkEvents;
  progressThrottleSeconds: number;
};

export type JobRequest = {
  urlTemplate: string;
  rangeText: string;
  volumeRangeText: string;
  combineVolume: boolean;
  addChapterTitle: boolean;
  barkConfig: BarkConfig;
};

export type DownloadJob = {
  id: string;
  sourceId: number;
  url: string;
  request: JobRequest;
  status: JobStatus;
  progress: number;
  message: string;
  title?: string;
  author?: string;
  sourceName?: string;
  volumeSummary?: string;
  error?: string;
  createdAt: string;
  startedAt?: string;
  finishedAt?: string;
  outputDir?: string;
  outputFiles: string[];
  webDavConfig?: WebDavConfig;
  uploadStatus?: "disabled" | "pending" | "uploading" | "succeeded" | "failed";
  uploadedFiles: string[];
  uploadError?: string;
  logs: string[];
};

export type WebDavConfig = {
  enabled: boolean;
  serverUrl: string;
  username: string;
  password?: string;
  basePath: string;
  hasPassword?: boolean;
  clearPassword?: boolean;
};

export type CleanupConfig = {
  enabled: boolean;
  retentionDays: number;
};

export type AutoUpdateItem = {
  jobId: string;
  enabled: boolean;
  baselineFingerprint?: string;
  lastCheckedAt?: string;
  lastUpdatedAt?: string;
  lastStatus?: string;
  lastMessage?: string;
};

export type AutoUpdateConfig = {
  enabled: boolean;
  dailyTime: string;
  lastRunAt?: string;
  items: AutoUpdateItem[];
};

export type AutoUpdateRunResult = {
  checked: number;
  updated: number;
  items: Array<{
    jobId: string;
    status: string;
    message: string;
  }>;
};

export type NovelPreview = {
  sourceId: number;
  id: string;
  url: string;
  sourceName: string;
  title: string;
  alias?: string;
  author: string;
  status: string;
  coverUrl?: string;
  tags: string[];
  publisher?: string;
  description?: string;
  volumeCount?: number;
  chapterCount?: number;
};

export type NovelPreviewFailure = {
  sourceId: number;
  url: string;
  message: string;
};

export type EventMessage =
  | { type: "jobs"; data: DownloadJob[]; ts: string }
  | { type: "job"; data: DownloadJob; ts: string }
  | { type: "jobDeleted"; data: { id: string }; ts: string }
  | { type: "heartbeat"; data: { message: string }; ts: string }
  | { type: "hello"; data: { message: string }; ts: string };
