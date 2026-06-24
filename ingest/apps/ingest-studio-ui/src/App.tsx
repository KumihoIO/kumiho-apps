import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { CSSProperties, Dispatch, SetStateAction } from "react";
import {
  createUserWithEmailAndPassword,
  onIdTokenChanged,
  signInWithEmailAndPassword,
  signOut
} from "firebase/auth";
import { open } from "@tauri-apps/plugin-dialog";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { appCacheDir, join } from "@tauri-apps/api/path";
import { mkdir, readFile, writeFile } from "@tauri-apps/plugin-fs";
import { convertFileSrc } from "@tauri-apps/api/core";
import { computeBoxes, type Box } from "./storyboard/slicing";
import { auth } from "./firebase";
import { callCommand, isTauri } from "./tauri";
import logoBlack from "../assets/kumiho_logo_black.png";
import logoWhite from "../assets/kumiho_logo_white.png";

type PythonEnvInfo = {
  app_data_dir: string;
  venv_dir: string;
  python_path: string;
  created: boolean;
};

type PanelEntry = {
  path: string;
  index?: number;
  name?: string;
  kind?: string;
  shotType?: string;
  cameraAngle?: string;
  cameraMove?: string;
  description?: string;
  width?: number;
  height?: number;
  item_kref?: string;
  revision_kref?: string;
  artifact_kref?: string;
};

type ParsedStoryboardPanel = {
  description: string;
  shotType: string;
  cameraAngle: string;
  cameraMove: string;
};

type StoryboardIngestReport = {
  bundleKref?: string;
  memberItemKrefs: string[];
  artifactKrefs: string[];
};

type IngestResult = {
  path: string;
  item_kref?: string;
  revision_kref?: string;
  artifact_kref?: string;
  artifact_path?: string;
};

type IngestError = {
  path: string | null;
  error: string;
};

type IngestResponse = {
  ok: boolean;
  count: number;
  results: IngestResult[];
  errors: IngestError[];
};

type FileItemSettings = {
  name: string;
  kind: string;
};

type LogEntry = {
  id: string;
  level: "info" | "warn" | "error";
  message: string;
  source: "ui" | "worker";
  timestamp: string;
};

type WorkerLogPayload = {
  level?: string;
  message?: string;
};

type ProjectSummary = {
  name: string;
  description?: string;
  allow_public?: boolean;
  deprecated?: boolean;
  project_id?: string;
};

type SpaceSummary = {
  name: string;
  path: string;
  type?: string;
  metadata?: Record<string, string>;
};

type ItemSummary = {
  kref?: string;
  item_name: string;
  kind: string;
  name?: string;
  project?: string;
  space?: string;
  metadata?: Record<string, string>;
};

const emptyEnv: PythonEnvInfo = {
  app_data_dir: "—",
  venv_dir: "—",
  python_path: "—",
  created: false
};

const SHOT_DESIGN_KIND = "shotdesign";
const DEFAULT_CAMERA_ANGLE = "EA";
const DEFAULT_CAMERA_MOVE = "FIX";

const SHOT_TYPE_OPTIONS = [
  { value: "ELS", label: "ELS ? Extreme Long Shot" },
  { value: "EWS", label: "EWS ? Extreme Wide Shot" },
  { value: "VWS", label: "VWS ? Very Wide Shot" },
  { value: "WS", label: "WS ? Wide Shot" },
  { value: "LS", label: "LS ? Long Shot" },
  { value: "FS", label: "FS ? Full Shot" },
  { value: "MS", label: "MS ? Medium Shot" },
  { value: "MCU", label: "MCU ? Medium Close-Up" },
  { value: "CU", label: "CU ? Close-Up" },
  { value: "ECU", label: "ECU ? Extreme Close-Up" },
  { value: "2S", label: "2S ? Two-Shot" },
  { value: "OTS", label: "OTS ? Over-The-Shoulder" },
  { value: "POV", label: "POV ? Point Of View" },
  { value: "INS", label: "INS ? Insert" },
  { value: "CI", label: "CI ? Cut-in" },
  { value: "CA", label: "CA ? Cutaway" },
  { value: "RX", label: "RX ? Reaction" },
  { value: "WIDE", label: "WIDE ? Wide lens" },
  { value: "NORM", label: "NORM ? Normal lens" },
  { value: "TELE", label: "TELE ? Telephoto" },
  { value: "MACRO", label: "MACRO ? Macro" },
  { value: "DOF", label: "DOF ? Depth of Field" },
  { value: "FG", label: "FG ? Foreground" },
  { value: "MG", label: "MG ? Midground" },
  { value: "BG", label: "BG ? Background" },
  { value: "BG_PLATE", label: "BG PLATE ? Background plate" },
  { value: "PLATE", label: "PLATE ? Clean plate" },
  { value: "DIRTY", label: "DIRTY ? Dirty frame" },
  { value: "SIL", label: "SIL ? Silhouette" },
  { value: "REVEAL", label: "REVEAL ? Reveal" }
];

const CAMERA_ANGLE_OPTIONS = [
  { value: "EA", label: "EA ? Eye Angle" },
  { value: "HA", label: "HA ? High Angle" },
  { value: "LA", label: "LA ? Low Angle" },
  { value: "OH", label: "OH ? Overhead / Bird’s-eye" },
  { value: "WA", label: "WA ? Worm’s-eye" },
  { value: "DT", label: "DT ? Dutch Tilt" },
  { value: "OS", label: "OS ? Over-Shoulder" },
  { value: "HIP", label: "HIP ? Hip-level" },
  { value: "KNEE", label: "KNEE ? Knee-level" },
  { value: "GS", label: "GS ? Ground Shot" }
];

const CAMERA_MOVE_OPTIONS = [
  { value: "FIX", label: "FIX ? Fixed" },
  { value: "PAN", label: "PAN ? Pan" },
  { value: "TILT", label: "TILT ? Tilt" },
  { value: "TRK", label: "TRK ? Track" },
  { value: "DOLLY", label: "DOLLY ? Dolly" },
  { value: "PI", label: "PI ? Push in" },
  { value: "PO", label: "PO ? Pull out" },
  { value: "CRAB", label: "CRAB ? Sideways dolly/track" },
  { value: "ARC", label: "ARC ? Arc" },
  { value: "BOOM", label: "BOOM ? Boom" },
  { value: "JIB", label: "JIB ? Jib" },
  { value: "CRANE", label: "CRANE ? Crane" },
  { value: "HAND", label: "HAND ? Handheld" },
  { value: "ST", label: "ST ? Steadicam" },
  { value: "GIM", label: "GIM ? Gimbal" },
  { value: "WHIP", label: "WHIP ? Whip pan" },
  { value: "RF", label: "RF ? Rack Focus" },
  { value: "ZI", label: "Z/I ? Zoom In" },
  { value: "ZO", label: "Z/O ? Zoom Out" },
  { value: "DI", label: "D/I ? Dolly In" },
  { value: "DO", label: "D/O ? Dolly Out" }
];

const SHOT_TYPE_CODES = [
  "ELS",
  "EWS",
  "VWS",
  "WS",
  "LS",
  "FS",
  "MS",
  "MCU",
  "CU",
  "ECU",
  "2S",
  "OTS",
  "POV",
  "INS",
  "CI",
  "CA",
  "RX"
];

const CAMERA_ANGLE_MATCHERS = [
  { code: "LA", phrases: ["low angle", "low-angle"] },
  { code: "HA", phrases: ["high angle", "high-angle"] },
  { code: "EA", phrases: ["eye angle", "eye-level", "eye level"] },
  { code: "DT", phrases: ["dutch tilt"] },
  { code: "OH", phrases: ["overhead", "bird's-eye", "birds-eye", "bird eye", "top-down", "top down"] },
  { code: "WA", phrases: ["worm's-eye", "worms-eye", "worm eye"] },
  { code: "OS", phrases: ["over-shoulder", "over shoulder", "over-the-shoulder"] },
  { code: "HIP", phrases: ["hip-level", "hip level"] },
  { code: "KNEE", phrases: ["knee-level", "knee level"] },
  { code: "GS", phrases: ["ground shot", "ground-level", "ground level"] }
];

const hasWord = (text: string, word: string) =>
  new RegExp(`\\b${word}\\b`, "i").test(text);

const findShotType = (text: string) => {
  const upper = text.toUpperCase();
  for (const code of SHOT_TYPE_CODES) {
    const pattern = new RegExp(`\\b${code}\\b`);
    if (pattern.test(upper)) {
      return code;
    }
  }
  return "";
};

const findCameraAngle = (text: string) => {
  const lower = text.toLowerCase();
  for (const matcher of CAMERA_ANGLE_MATCHERS) {
    if (matcher.phrases.some((phrase) => lower.includes(phrase))) {
      return matcher.code;
    }
  }
  return "";
};

const findCameraMove = (text: string) => {
  const lower = text.toLowerCase();
  if (/\bdolly in\b/.test(lower)) {
    return "DI";
  }
  if (/\bdolly out\b/.test(lower)) {
    return "DO";
  }
  if (/\bpush in\b/.test(lower)) {
    return "PI";
  }
  if (/\bpull out\b/.test(lower)) {
    return "PO";
  }
  if (/\bzoom in\b/.test(lower)) {
    return "ZI";
  }
  if (/\bzoom out\b/.test(lower)) {
    return "ZO";
  }
  if (/\borbit\w*\b/.test(lower) || hasWord(lower, "arc")) {
    return "ARC";
  }
  if (hasWord(lower, "pan")) {
    return "PAN";
  }
  if (hasWord(lower, "tilt")) {
    return "TILT";
  }
  if (hasWord(lower, "track")) {
    return "TRK";
  }
  if (hasWord(lower, "crab")) {
    return "CRAB";
  }
  if (hasWord(lower, "boom")) {
    return "BOOM";
  }
  if (hasWord(lower, "jib")) {
    return "JIB";
  }
  if (hasWord(lower, "crane")) {
    return "CRANE";
  }
  if (hasWord(lower, "handheld")) {
    return "HAND";
  }
  if (hasWord(lower, "steadicam")) {
    return "ST";
  }
  if (hasWord(lower, "gimbal")) {
    return "GIM";
  }
  if (hasWord(lower, "whip")) {
    return "WHIP";
  }
  if (/\brack focus\b/.test(lower)) {
    return "RF";
  }
  return "";
};

const parseStoryboardNotes = (raw: string) => {
  const normalized = raw.replace(/\r\n/g, "\n").trim();
  if (!normalized) {
    return [] as ParsedStoryboardPanel[];
  }
  return normalized
    .split(/\n{2,}/)
    .map((block) => {
      const lines = block
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean);
      if (!lines.length) {
        return null;
      }
      const header = lines[0];
      const description = lines.slice(1).join("\n").trim();
      const parts = header
        .split("|")
        .map((part) => part.trim())
        .filter(Boolean);
      const lastSegment = parts.length ? parts[parts.length - 1] : header;
      const searchText = [lastSegment, description].filter(Boolean).join(" ");
      const shotType = findShotType(searchText);
      const cameraAngle = findCameraAngle(searchText) || DEFAULT_CAMERA_ANGLE;
      const cameraMove = findCameraMove(searchText) || DEFAULT_CAMERA_MOVE;
      return {
        description,
        shotType,
        cameraAngle,
        cameraMove
      };
    })
    .filter((panel): panel is ParsedStoryboardPanel => panel !== null);
};

const applyStoryboardNotesToPanels = (notes: string, panels: PanelEntry[]) => {
  const parsed = parseStoryboardNotes(notes);
  if (!parsed.length) {
    return panels;
  }
  return panels.map((panel, index) => {
    const parsedEntry = parsed[index];
    if (!parsedEntry) {
      return panel;
    }
    return {
      ...panel,
      description: parsedEntry.description || panel.description,
      shotType: parsedEntry.shotType || panel.shotType,
      cameraAngle: parsedEntry.cameraAngle || panel.cameraAngle,
      cameraMove: parsedEntry.cameraMove || panel.cameraMove
    };
  });
};

const getShotDesignParts = (panel: PanelEntry) => {
  const shotType = (panel.shotType ?? "").trim();
  const cameraAngle = (panel.cameraAngle ?? "").trim();
  const cameraMove = (panel.cameraMove ?? "").trim();
  return { shotType, cameraAngle, cameraMove };
};

const buildShotDesignName = (panel: PanelEntry) => {
  const { shotType, cameraAngle, cameraMove } = getShotDesignParts(panel);
  if (!shotType || !cameraAngle || !cameraMove) {
    return "";
  }
  return `${shotType}_${cameraAngle}_${cameraMove}`;
};

export default function App() {
  const [envInfo, setEnvInfo] = useState<PythonEnvInfo>(emptyEnv);
  const [envStatus, setEnvStatus] = useState("Idle");
  const [workerStatus, setWorkerStatus] = useState("Not running");
  const [tokenStatus, setTokenStatus] = useState("No token");
  const [authStatus, setAuthStatus] = useState("Signed out");
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [projectName, setProjectName] = useState("");
  const [spaceName, setSpaceName] = useState("");
  const [subSpacePath, setSubSpacePath] = useState("");
  const [itemName, setItemName] = useState("");
  const [itemKind, setItemKind] = useState("file");
  const [multiFileMode, setMultiFileMode] = useState<"per_file" | "single_item">(
    "per_file"
  );
  const [fileItemSettings, setFileItemSettings] = useState<Record<string, FileItemSettings>>(
    {}
  );
  const [projectOptions, setProjectOptions] = useState<string[]>([]);
  const [spaceOptions, setSpaceOptions] = useState<string[]>([]);
  // Full selected space paths, one per depth: ['/project/root', '/project/root/child', ...]
  const [spaceHierarchy, setSpaceHierarchy] = useState<string[]>([]);
  const [itemKindOptions, setItemKindOptions] = useState(["file", "image", "video", "audio"]);

  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [spaces, setSpaces] = useState<SpaceSummary[]>([]);
  const [selectedSpacePath, setSelectedSpacePath] = useState<string | null>(null);
  const [spaceItems, setSpaceItems] = useState<ItemSummary[]>([]);
  const [browseStatus, setBrowseStatus] = useState("Idle");
  const [filePaths, setFilePaths] = useState("");
  const [selectedPaths, setSelectedPaths] = useState<string[]>([]);
  const [dropStatus, setDropStatus] = useState("Drop files here");
  const [moveFiles, setMoveFiles] = useState(false);
  const [moveRoot, setMoveRoot] = useState("");
  const [ingestStatus, setIngestStatus] = useState("Idle");
  const [ingestBusy, setIngestBusy] = useState(false);
  const [ingestResults, setIngestResults] = useState<IngestResponse | null>(null);
  const [sdkStatus, setSdkStatus] = useState("Idle");
  const [storyboardPath, setStoryboardPath] = useState<string | null>(null);
  const [storyboardUrl, setStoryboardUrl] = useState<string | null>(null);
  const [storyboardWidth, setStoryboardWidth] = useState(0);
  const [storyboardHeight, setStoryboardHeight] = useState(0);
  const [gridRows, setGridRows] = useState(3);
  const [gridCols, setGridCols] = useState(3);
  const [marginPx, setMarginPx] = useState(0);
  const [gutterPx, setGutterPx] = useState(0);
  const [offsetX, setOffsetX] = useState(0);
  const [offsetY, setOffsetY] = useState(0);
  const [bundleName] = useState("storyboard-sequence");
  const [bundleTag, setBundleTag] = useState("ingested");
  const [storyboardNotes, setStoryboardNotes] = useState("");
  const [storyboardResults, setStoryboardResults] = useState<StoryboardIngestReport | null>(null);
  const [panelEntries, setPanelEntries] = useState<PanelEntry[]>([]);
  const [preparedBoxes, setPreparedBoxes] = useState<Box[] | null>(null);
  const [storyboardStatus, setStoryboardStatus] = useState("Idle");
  const [storyboardBusy, setStoryboardBusy] = useState(false);
  const [storyboardWarnings, setStoryboardWarnings] = useState<string[]>([]);
  const [storyboardError, setStoryboardError] = useState<string | null>(null);
  const imageRef = useRef<HTMLImageElement | null>(null);
  const storyboardObjectUrl = useRef<string | null>(null);
  const [activeDropTarget, setActiveDropTarget] = useState<"ingest" | "storyboard">(
    "ingest"
  );
  const [isTauriEnv, setIsTauriEnv] = useState(() => isTauri());
  const workerAutoStart = useRef(false);
  const workerRestartedAfterAuth = useRef(false);
  const workerRestartInProgress = useRef(false);
  const [activeView, setActiveView] = useState<"settings" | "ingest" | "storyboard">(
    "ingest"
  );
  const [theme, setTheme] = useState<"dark" | "light">(() => {
    if (typeof window === "undefined") {
      return "dark";
    }
    const stored = window.localStorage.getItem("kumiho-ingest-theme");
    return stored === "light" ? "light" : "dark";
  });
  const [localServerEnabled, setLocalServerEnabled] = useState<boolean>(() => {
    if (typeof window === "undefined") return false;
    return window.localStorage.getItem("kumiho-ingest-local-server-enabled") === "1";
  });
  const [localServerAddr, setLocalServerAddr] = useState<string>(() => {
    if (typeof window === "undefined") return "127.0.0.1:9190";
    return window.localStorage.getItem("kumiho-ingest-local-server-addr") || "127.0.0.1:9190";
  });
  const [localServerStatus, setLocalServerStatus] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);

  const appendLog = useCallback(
    (level: LogEntry["level"], message: string, source: LogEntry["source"] = "ui") => {
      const timestamp = new Date().toLocaleTimeString();
      const entry: LogEntry = {
        id: `${Date.now()}-${Math.random().toString(16).slice(2)}`,
        level,
        message,
        source,
        timestamp
      };
      setLogs((prev) => {
        const next = [...prev, entry];
        return next.slice(-200);
      });
    },
    []
  );

  const formatError = useCallback((err: unknown) => {
    if (err instanceof Error && err.message) {
      return err.message;
    }
    if (typeof err === "string") {
      return err;
    }
    if (err && typeof err === "object") {
      const message = (err as { message?: unknown }).message;
      if (typeof message === "string") {
        return message;
      }
      try {
        return JSON.stringify(err);
      } catch {
        return "Unknown error";
      }
    }
    return "Unknown error";
  }, []);

  const refreshAuthToken = useCallback(
    async (force = false) => {
      const user = auth.currentUser;
      if (!user) {
        return null;
      }
      try {
        const token = await user.getIdToken(force);
        setTokenStatus(force ? "Token refreshed." : "Token ready.");
        if (isTauriEnv) {
          await callCommand("set_auth_token", { token });
          await callCommand("store_auth_token_secure", { token });
        }
        return token;
      } catch (err) {
        setTokenStatus("Token refresh failed.");
        setError(formatError(err));
        appendLog("error", `Token refresh failed: ${formatError(err)}`);
        return null;
      }
    },
    [appendLog, formatError, isTauriEnv]
  );

  const addOption = useCallback(
    (value: string, setList: Dispatch<SetStateAction<string[]>>) => {
      const nextValue = value.trim();
      if (!nextValue) {
        return;
      }
      setList((prev) => (prev.includes(nextValue) ? prev : [...prev, nextValue]));
    },
    []
  );

  const environmentNote = useMemo(() => {
    if (!isTauriEnv) {
      return "Web preview mode: Tauri APIs are not available.";
    }
    return "Desktop mode: Tauri APIs are available.";
  }, [isTauriEnv]);

  useEffect(() => {
    if (typeof document === "undefined") {
      return;
    }
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
    if (typeof window !== "undefined") {
      window.localStorage.setItem("kumiho-ingest-theme", theme);
    }
  }, [theme]);

  const splitSpacePath = useCallback(
    (project: string, spacePath: string) => {
      const trimmed = spacePath.trim();
      if (!trimmed) {
        return { spaceName: "", spaceParentPath: undefined as string | undefined };
      }
      const normalized = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
      const parts = normalized.split("/").filter(Boolean);
      if (!parts.length) {
        return { spaceName: "", spaceParentPath: undefined as string | undefined };
      }
      // Expect: /{project}/.../spaceName
      const projectIndex = parts[0] === project ? 0 : -1;
      const tail = projectIndex === 0 ? parts.slice(1) : parts;
      const spaceNameValue = tail[tail.length - 1] ?? "";
      if (tail.length <= 1) {
        return { spaceName: spaceNameValue, spaceParentPath: undefined };
      }
      const parentTail = tail.slice(0, -1);
      return {
        spaceName: spaceNameValue,
        spaceParentPath: `/${project}/${parentTail.join("/")}`
      };
    },
    []
  );

  const spaceLastSegment = useCallback((spacePath: string) => {
    const trimmed = spacePath.trim();
    if (!trimmed) {
      return "";
    }
    const normalized = trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
    const parts = normalized.split("/").filter(Boolean);
    return parts.length ? parts[parts.length - 1] : "";
  }, []);

  const buildSpaceHierarchyFromPath = useCallback((project: string, spacePath: string) => {
    const trimmedProject = project.trim();
    const trimmedPath = spacePath.trim();
    if (!trimmedProject || !trimmedPath) {
      return [] as string[];
    }
    const normalized = trimmedPath.startsWith("/") ? trimmedPath : `/${trimmedPath}`;
    const parts = normalized.split("/").filter(Boolean);
    const tail = parts[0] === trimmedProject ? parts.slice(1) : parts;
    const hierarchy: string[] = [];
    let current = `/${trimmedProject}`;
    for (const segment of tail) {
      current = `${current}/${segment}`;
      hierarchy.push(current);
    }
    return hierarchy;
  }, []);

  const getImmediateChildSpaceNames = useCallback(
    (project: string, parentPath: string | null, knownSpaces: SpaceSummary[]) => {
      const trimmedProject = project.trim();
      if (!trimmedProject || !knownSpaces.length) {
        return [] as string[];
      }

      const names = new Set<string>();

      if (!parentPath) {
        const expectedPrefix = `/${trimmedProject}/`;
        for (const space of knownSpaces) {
          if (!space.path.startsWith(expectedPrefix)) {
            continue;
          }
          const tail = space.path.slice(expectedPrefix.length);
          if (!tail || tail.includes("/")) {
            continue;
          }
          names.add(space.name || tail);
        }
      } else {
        const parent = parentPath.trim().startsWith("/") ? parentPath.trim() : `/${parentPath.trim()}`;
        const expectedPrefix = `${parent}/`;
        for (const space of knownSpaces) {
          if (!space.path.startsWith(expectedPrefix)) {
            continue;
          }
          const tail = space.path.slice(expectedPrefix.length);
          if (!tail || tail.includes("/")) {
            continue;
          }
          names.add(space.name || tail);
        }
      }

      return Array.from(names).sort((a, b) => a.localeCompare(b));
    },
    []
  );

  const normalizeSelectedSpacePath = useCallback(
    (project: string, parentPath: string | null, value: string) => {
      const trimmedProject = project.trim();
      const trimmed = value.trim();
      if (!trimmedProject || !trimmed) {
        return null;
      }

      // Allow full paths ("/project/a/b") or plain segments ("b").
      if (trimmed.startsWith("/")) {
        return trimmed;
      }
      if (trimmed.includes("/")) {
        return `/${trimmed}`;
      }

      if (!parentPath) {
        return `/${trimmedProject}/${trimmed}`;
      }
      const parent = parentPath.trim().startsWith("/") ? parentPath.trim() : `/${parentPath.trim()}`;
      return `${parent}/${trimmed}`;
    },
    []
  );

  const refreshProjects = useCallback(async () => {
    if (!isTauriEnv || !isAuthenticated) {
      return;
    }
    setBrowseStatus("Loading projects...");
    try {
      const response = await callCommand<{ projects: ProjectSummary[] }>("list_projects", {
        payload: {}
      });
      const next = response.projects ?? [];
      setProjects(next);
      const nextProjectNames = next.map((p) => p.name).filter(Boolean);
      setProjectOptions(nextProjectNames);
      // If the current project isn't valid, clear dependent state.
      if (projectName.trim() && !nextProjectNames.includes(projectName.trim())) {
        setProjectName("");
        setSpaces([]);
        setSpaceItems([]);
        setSelectedSpacePath(null);
        setSpaceName("");
        setSubSpacePath("");
        setSpaceHierarchy([]);
      }
      setBrowseStatus("Projects loaded.");
    } catch (err) {
      setBrowseStatus("Failed to load projects.");
      appendLog("warn", `Project list failed: ${formatError(err)}`);
    }
  }, [appendLog, formatError, isAuthenticated, isTauriEnv, projectName]);

  const refreshSpaces = useCallback(
    async (project: string) => {
      if (!isTauriEnv || !isAuthenticated) {
        return;
      }
      const trimmed = project.trim();
      if (!trimmed) {
        return;
      }
      setBrowseStatus("Loading spaces...");
      try {
        const response = await callCommand<{ spaces: SpaceSummary[] }>("list_spaces", {
          payload: {
            project_name: trimmed,
            recursive: true
          }
        });
        const nextSpaces = response.spaces ?? [];
        setSpaces(nextSpaces);
        // Populate the datalists with suggested values.
        const rootChildren = nextSpaces
          .filter((space) => {
            const expectedPrefix = `/${trimmed}/`;
            if (!space.path.startsWith(expectedPrefix)) {
              return false;
            }
            const tail = space.path.slice(expectedPrefix.length);
            return tail.length > 0 && !tail.includes("/");
          })
          .map((space) => space.name);
        setSpaceOptions((prev) => {
          const merged = new Set([...(rootChildren.length ? rootChildren : prev)]);
          return Array.from(merged);
        });
        setSpaceHierarchy([]);
        setBrowseStatus("Spaces loaded.");
      } catch (err) {
        setBrowseStatus("Failed to load spaces.");
        appendLog("warn", `Space list failed: ${formatError(err)}`);
      }
    },
    [appendLog, formatError, isAuthenticated, isTauriEnv]
  );

  const refreshItemsForSpace = useCallback(
    async (project: string, spacePath: string) => {
      if (!isTauriEnv || !isAuthenticated) {
        return;
      }
      const trimmedProject = project.trim();
      const trimmedPath = spacePath.trim();
      if (!trimmedProject || !trimmedPath) {
        return;
      }
      setBrowseStatus("Loading items...");
      try {
        const response = await callCommand<{ items: ItemSummary[] }>("list_items", {
          payload: {
            project_name: trimmedProject,
            space_path: trimmedPath
          }
        });
        setSpaceItems(response.items ?? []);
        setBrowseStatus("Items loaded.");
      } catch (err) {
        setBrowseStatus("Failed to load items.");
        appendLog("warn", `Item list failed: ${formatError(err)}`);
      }
    },
    [appendLog, formatError, isAuthenticated, isTauriEnv]
  );

  useEffect(() => {
    setIsTauriEnv(isTauri());
  }, []);

  useEffect(() => {
    if (!isTauriEnv) {
      return;
    }
    let unlisten: (() => void) | undefined;
    listen<WorkerLogPayload>("worker-log", (event) => {
      const payload = event.payload as unknown;
      let level: LogEntry["level"] = "info";
      let message = "";
      if (typeof payload === "string") {
        message = payload;
      } else if (payload && typeof payload === "object") {
        const parsed = payload as WorkerLogPayload;
        message = parsed.message ?? JSON.stringify(payload);
        if (parsed.level === "error" || parsed.level === "warn") {
          level = parsed.level;
        }
      } else {
        message = String(payload ?? "");
      }
      appendLog(level, message, "worker");
    })
      .then((unsubscribe) => {
        unlisten = unsubscribe;
      })
      .catch((err) => {
        appendLog("warn", `Failed to listen for worker logs: ${formatError(err)}`);
      });

    return () => {
      if (unlisten) {
        unlisten();
      }
    };
  }, [appendLog, isTauriEnv]);

  useEffect(() => {
    // Load projects after auth in desktop mode.
    if (!isTauriEnv || !isAuthenticated) {
      return;
    }
    refreshProjects();
  }, [isAuthenticated, isTauriEnv, refreshProjects]);

  useEffect(() => {
    // If user navigates to ingest with an empty project field, refresh projects
    // so the datalist is populated.
    if (!isTauriEnv || !isAuthenticated) {
      return;
    }
    if (activeView !== "ingest") {
      return;
    }
    if (projectName.trim()) {
      return;
    }
    refreshProjects();
  }, [activeView, isAuthenticated, isTauriEnv, projectName, refreshProjects]);

  useEffect(() => {
    if (!isTauriEnv || !isAuthenticated) {
      return;
    }
    const handle = window.setTimeout(() => {
      const trimmed = projectName.trim();
      if (!trimmed) {
        return;
      }
      // Only load spaces after user selects a real project.
      // (Typing into the editable combobox should not trigger requests.)
      if (!projects.some((p) => p.name === trimmed)) {
        return;
      }
      // Clear stale state before loading.
      setSpaces([]);
      setSpaceItems([]);
      setSelectedSpacePath(null);
      setSpaceHierarchy([]);
      setSpaceName("");
      setSubSpacePath("");
      refreshSpaces(trimmed);
    }, 450);
    return () => window.clearTimeout(handle);
  }, [isAuthenticated, isTauriEnv, projectName, projects, refreshSpaces]);

  useEffect(() => {
    // Keep ingest fields in sync with the deepest selected space.
    const trimmedProject = projectName.trim();
    if (!trimmedProject) {
      setSelectedSpacePath(null);
      setSpaceName("");
      setSubSpacePath("");
      return;
    }

    const deepest = spaceHierarchy.length ? spaceHierarchy[spaceHierarchy.length - 1] : "";
    if (!deepest) {
      setSelectedSpacePath(null);
      setSpaceName("");
      setSubSpacePath("");
      return;
    }

    setSelectedSpacePath(deepest);
    const split = splitSpacePath(trimmedProject, deepest);
    setSpaceName(split.spaceName);
    setSubSpacePath(split.spaceParentPath ?? "");
  }, [projectName, spaceHierarchy, splitSpacePath]);

  const spaceLevelOptions = useMemo(() => {
    const trimmedProject = projectName.trim();
    if (!trimmedProject) {
      return [{ label: "Space", options: spaceOptions }] as Array<{
        label: string;
        options: string[];
      }>;
    }

    const levels: Array<{ label: string; options: string[] }> = [];
    const rootOptions = getImmediateChildSpaceNames(trimmedProject, null, spaces);
    levels.push({ label: "Space", options: rootOptions.length ? rootOptions : spaceOptions });

    for (let depth = 1; depth < 12; depth += 1) {
      const parent = spaceHierarchy[depth - 1];
      if (!parent) {
        break;
      }
      const opts = getImmediateChildSpaceNames(trimmedProject, parent, spaces);
      if (!opts.length) {
        break;
      }
      levels.push({ label: "Sub-space", options: opts });
    }
    return levels;
  }, [getImmediateChildSpaceNames, projectName, spaceHierarchy, spaceOptions, spaces]);

  const handleSpaceLevelChange = useCallback(
    (levelIndex: number, value: string) => {
      const trimmedProject = projectName.trim();
      if (!trimmedProject) {
        return;
      }

      setSpaceItems([]);
      setSpaceHierarchy((prev) => {
        const next = prev.slice(0, levelIndex);
        const parent = levelIndex === 0 ? null : next[levelIndex - 1] ?? null;
        const fullPath = normalizeSelectedSpacePath(trimmedProject, parent, value);
        if (fullPath) {
          next.push(fullPath);
        }
        return next;
      });
    },
    [normalizeSelectedSpacePath, projectName]
  );

  const sliceResult = useMemo(
    () =>
      computeBoxes({
        width: storyboardWidth,
        height: storyboardHeight,
        rows: gridRows,
        cols: gridCols,
        margin: marginPx,
        gutter: gutterPx,
        offsetX,
        offsetY
      }),
    [storyboardWidth, storyboardHeight, gridRows, gridCols, marginPx, gutterPx, offsetX, offsetY]
  );

  const panelAspect = useMemo(() => {
    const firstBox = preparedBoxes?.[0] ?? sliceResult.boxes[0];
    if (firstBox && firstBox.width > 0 && firstBox.height > 0) {
      return firstBox.width / firstBox.height;
    }
    return 16 / 9;
  }, [preparedBoxes, sliceResult.boxes]);

  const storyboardCanIngest = useMemo(() => {
    const hasProject = projectName.trim().length > 0;
    const hasSpace = spaceName.trim().length > 0;
    const panelsComplete =
      panelEntries.length > 0 &&
      panelEntries.every((panel) => buildShotDesignName(panel).length > 0);
    return (
      isAuthenticated &&
      isTauriEnv &&
      Boolean(storyboardPath) &&
      hasProject &&
      hasSpace &&
      panelsComplete
    );
  }, [isAuthenticated, isTauriEnv, panelEntries, projectName, spaceName, storyboardPath]);

  useEffect(() => {
    setStoryboardWarnings(sliceResult.warnings);
    if (!storyboardUrl) {
      return;
    }
    if (sliceResult.error === "Image dimensions are not available yet.") {
      setStoryboardError(null);
      return;
    }
    setStoryboardError(sliceResult.error ?? null);
  }, [sliceResult, storyboardUrl]);

  useEffect(() => {
    if (!panelEntries.length) {
      return;
    }
    setPanelEntries([]);
    setPreparedBoxes(null);
  }, [gridRows, gridCols, marginPx, gutterPx, offsetX, offsetY]);

  type NormalizePathsResult = { paths: string[] } | { error: string };

  const validateLocalPath = useCallback((path: string): string | null => {
    if (!path) {
      return "Unable to read selected file path.";
    }
    const trimmed = path.trim();
    if (!trimmed) {
      return "Selected path is empty.";
    }
    if (trimmed.length !== path.length) {
      return "Paths cannot start or end with whitespace.";
    }
    if (/[,\r\n\t]/.test(path)) {
      return "File paths cannot include commas, tabs, or newline characters.";
    }
    return null;
  }, []);

  const normalizePathsWithValidation = useCallback(
    (paths: string[]): NormalizePathsResult => {
      const sanitized: string[] = [];
      for (const path of paths) {
        const validationError = validateLocalPath(path);
        if (validationError) {
          return { error: validationError };
        }
        sanitized.push(path.trim());
      }
      return { paths: sanitized };
    },
    [validateLocalPath]
  );

  const handleChooseStoryboard = async () => {
    setStoryboardError(null);
    if (!isTauriEnv) {
      setStoryboardError("Storyboard selection is only available in the desktop app.");
      return;
    }
    try {
      const selected = await open({
        multiple: false,
        title: "Select a contact sheet image",
        filters: [
          {
            name: "Images",
            extensions: ["png", "jpg", "jpeg", "webp"]
          }
        ]
      });
      if (!selected || Array.isArray(selected)) {
        return;
      }
      const selectedPath =
        typeof selected === "string"
          ? selected
          : typeof (selected as { path?: unknown }).path === "string"
            ? (selected as { path: string }).path
            : null;
      if (!selectedPath) {
        setStoryboardError("Unable to read selected file path.");
        return;
      }
      const validationError = validateLocalPath(selectedPath);
      if (validationError) {
        setStoryboardError(validationError);
        return;
      }
      const sanitizedPath = selectedPath.trim();

      const normalizedForCheck = sanitizedPath.split("?")[0].split("#")[0].trim().toLowerCase();
      if (!normalizedForCheck.endsWith(".png") && !normalizedForCheck.endsWith(".jpg") && !normalizedForCheck.endsWith(".jpeg") && !normalizedForCheck.endsWith(".webp")) {
        setStoryboardError("Please select a PNG, JPG, or WEBP contact sheet.");
        return;
      }
      setStoryboardPath(sanitizedPath);
      setStoryboardUrl(await loadStoryboardPreviewUrl(sanitizedPath));
      setPanelEntries([]);
      setPreparedBoxes(null);
      setStoryboardStatus("Contact sheet loaded.");
    } catch (err) {
      setStoryboardError(formatError(err));
    }
  };

  const handleClearStoryboard = () => {
    resetStoryboardSelection();
  };


  const handleCutAndPrep = async (dims?: { width: number; height: number }) => {
    setStoryboardError(null);
    if (!isTauriEnv) {
      setStoryboardError("Storyboard ingest requires the desktop app.");
      return;
    }
    const image = imageRef.current;
    if (!image || !storyboardPath) {
      setStoryboardError("Select a storyboard image first.");
      return;
    }
    const computed = computeBoxes({
      width: dims?.width ?? storyboardWidth,
      height: dims?.height ?? storyboardHeight,
      rows: gridRows,
      cols: gridCols,
      margin: marginPx,
      gutter: gutterPx,
      offsetX,
      offsetY
    });
    if (computed.error) {
      setStoryboardError(computed.error);
      return;
    }
    if (!computed.boxes.length) {
      setStoryboardError("Check the grid settings.");
      return;
    }
    setPreparedBoxes(computed.boxes);
    setStoryboardStatus("Slicing and saving panels...");
    setStoryboardBusy(true);
    try {
      const root = await appCacheDir();
      const targetDir = await join(root, "kumiho-storyboard", Date.now().toString());
      await mkdir(targetDir, { recursive: true });
      const createdPanels: PanelEntry[] = [];
      for (let index = 0; index < computed.boxes.length; index += 1) {
        const box = computed.boxes[index];
        const canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(box.width));
        canvas.height = Math.max(1, Math.round(box.height));
        const ctx = canvas.getContext("2d");
        if (!ctx) {
          throw new Error("Failed to create canvas context.");
        }
        ctx.drawImage(
          image,
          box.x,
          box.y,
          box.width,
          box.height,
          0,
          0,
          canvas.width,
          canvas.height
        );
        const blob = await new Promise<Blob>((resolve, reject) => {
          canvas.toBlob((result) => {
            if (!result) {
              reject(new Error("Failed to encode panel image."));
              return;
            }
            resolve(result);
          }, "image/png");
        });
        const buffer = new Uint8Array(await blob.arrayBuffer());
        const filename = `panel_${String(index + 1).padStart(2, "0")}.png`;
        const outputPath = await join(targetDir, filename);
        await writeFile(outputPath, buffer);
        const shotCode = String(index + 1).padStart(3, "0");
        createdPanels.push({
          path: outputPath,
          index,
          name: shotCode,
          kind: SHOT_DESIGN_KIND,
          shotType: "",
          cameraAngle: "",
          cameraMove: "",
          description: "",
          width: Math.round(box.width),
          height: Math.round(box.height)
        });
      }

      const hydratedPanels = storyboardNotes.trim()
        ? applyStoryboardNotesToPanels(storyboardNotes, createdPanels)
        : createdPanels;
      setPanelEntries(hydratedPanels);
      setStoryboardStatus("Panels prepped. Review card fields, then ingest.");
    } catch (err) {
      setStoryboardStatus("Storyboard prep failed.");
      setStoryboardError(formatError(err));
    } finally {
      setStoryboardBusy(false);
    }
  };

  const handleIngestAndBundle = async () => {
    setError(null);
    if (!isAuthenticated) {
      setError("Sign in to ingest storyboard panels.");
      return;
    }
    setStoryboardResults(null);
    await refreshAuthToken(true);
    if (!isTauriEnv) {
      setError("Storyboard ingest requires the desktop app.");
      return;
    }
    if (!storyboardPath) {
      setError("Select a storyboard image first.");
      return;
    }
    if (!panelEntries.length) {
      setError("Cut & Prep first.");
      return;
    }

    setStoryboardStatus("Ingesting cards and bundling...");
    setStoryboardBusy(true);

    // Scroll to top of the storyboard section to show loading overlay
    document.getElementById("storyboard")?.scrollIntoView({ behavior: "smooth", block: "start" });

    // Allow React to render the loading overlay before starting heavy work
    await new Promise(resolve => setTimeout(resolve, 50));

    try {
      const payloadPanels = panelEntries.map((panel, index) => {
        const shotIndex = panel.index ?? index;
        const fallbackCode = String(shotIndex + 1).padStart(3, "0");
        const shotCode = (panel.name || "").trim() || fallbackCode;
        const { shotType, cameraAngle, cameraMove } = getShotDesignParts(panel);
        const shotDesignName = buildShotDesignName(panel);
        const shotDescription = panel.description ?? "";
        const shotWidth = panel.width ?? null;
        const shotHeight = panel.height ?? null;
        return {
          path: panel.path,
          index: shotIndex,
          name: shotCode,
          kind: SHOT_DESIGN_KIND,
          item_name: shotDesignName,
          item_kind: SHOT_DESIGN_KIND,
          shot_code: shotCode,
          shot_type: shotType,
          camera_angle: cameraAngle,
          camera_move: cameraMove,
          description: shotDescription,
          shot_index: shotIndex,
          shot_name: shotCode,
          shot_camera: shotDesignName,
          shot_description: shotDescription,
          width: shotWidth,
          height: shotHeight
        };
      });

      const trimmedBundleTag = bundleTag.trim();
      const response = await callCommand<{
        panels: PanelEntry[];
        bundle_kref?: string;
      }>("storyboard_ingest", {
        payload: {
          project_name: projectName,
          space_name: spaceName,
          space_parent_path: subSpacePath || undefined,
          bundle_name: bundleName,
          bundle_tag: trimmedBundleTag || undefined,
          contact_sheet_name: "storyboard.contactshet",
          contact_sheet_path: storyboardPath,
          move_files: moveFiles,
          move_root: moveFiles ? moveRoot : undefined,
          source: {
            type: "contact_sheet",
            rows: gridRows,
            cols: gridCols,
            margin_px: marginPx,
            gutter_px: gutterPx,
            image_width: storyboardWidth,
            image_height: storyboardHeight
          },
          panels: payloadPanels
        }
      });

      const responsePanels = response.panels ?? [];
      const byPath = new Map(responsePanels.map((panel) => [panel.path, panel]));
      setPanelEntries((prev) =>
        prev.map((panel) => {
          const update = byPath.get(panel.path);
          if (!update) {
            return panel;
          }
          return {
            ...panel,
            item_kref: update.item_kref ?? panel.item_kref,
            revision_kref: update.revision_kref ?? panel.revision_kref,
            artifact_kref: update.artifact_kref ?? panel.artifact_kref
          };
        })
      );
      const memberItemKrefs = Array.from(
        new Set(
          responsePanels
            .map((panel) => panel.item_kref)
            .filter((kref): kref is string => Boolean(kref))
        )
      );
      const artifactKrefs = Array.from(
        new Set(
          responsePanels
            .map((panel) => panel.artifact_kref)
            .filter((kref): kref is string => Boolean(kref))
        )
      );
      setStoryboardResults({
        bundleKref: response.bundle_kref,
        memberItemKrefs,
        artifactKrefs
      });
      setStoryboardStatus("Storyboard ingest complete.");
      resetStoryboardSelection(true);
    } catch (err) {
      setStoryboardStatus("Storyboard ingest failed.");
      setError(formatError(err));
    } finally {
      setStoryboardBusy(false);
    }
  };

  const handleEnsureEnv = async () => {
    setError(null);
    setEnvStatus("Preparing Python environment...");
    appendLog("info", "Ensuring Python environment...");
    try {
      const info = await callCommand<PythonEnvInfo>("ensure_python_env");
      setEnvInfo(info);
      setEnvStatus(info.created ? "Environment created." : "Environment ready.");
      appendLog("info", "Python environment ready.");
    } catch (err) {
      setError(formatError(err));
      setEnvStatus("Failed to prepare environment.");
      appendLog("error", `Ensure env failed: ${formatError(err)}`);
    }
  };

  const handleUpdateSdk = async () => {
    setError(null);
    setSdkStatus("Updating SDK...");
    appendLog("info", "Updating kumiho SDK...");
    try {
      const info = await callCommand<PythonEnvInfo>("update_kumiho_sdk");
      setEnvInfo(info);
      setSdkStatus("SDK updated.");
      appendLog("info", "SDK updated.");
    } catch (err) {
      setSdkStatus("SDK update failed.");
      setError(formatError(err));
      appendLog("error", `SDK update failed: ${formatError(err)}`);
    }
  };

  const handleSaveLocalServer = async () => {
    setError(null);
    setLocalServerStatus("Applying...");
    const addr = localServerEnabled ? localServerAddr.trim() : null;
    try {
      window.localStorage.setItem(
        "kumiho-ingest-local-server-enabled",
        localServerEnabled ? "1" : "0",
      );
      window.localStorage.setItem("kumiho-ingest-local-server-addr", localServerAddr.trim());
      await callCommand("set_local_server", { addr });
      await callCommand("restart_python_worker");
      setLocalServerStatus(
        localServerEnabled
          ? `Connected to local server ${addr} (no sign-in required)`
          : "Using Kumiho Cloud",
      );
      appendLog(
        "info",
        localServerEnabled ? `Local/CE server enabled: ${addr}` : "Local server disabled (cloud).",
      );
    } catch (err) {
      setError(formatError(err));
      setLocalServerStatus("Failed to apply.");
      appendLog("error", `Local server update failed: ${formatError(err)}`);
    }
  };

  const handleStartWorker = async () => {
    setError(null);
    setWorkerStatus("Starting...");
    appendLog("info", "Starting Python worker...");
    try {
      await callCommand("start_python_worker");
      setWorkerStatus("Running (stdio JSON-RPC placeholder)");
      appendLog("info", "Python worker started.");
    } catch (err) {
      setError(formatError(err));
      setWorkerStatus("Failed to start.");
      appendLog("error", `Worker start failed: ${formatError(err)}`);
    }
  };

  const handleSetToken = async () => {
    setError(null);
    setTokenStatus("Sending token...");
    try {
      await callCommand("set_auth_token", { token: "demo-token" });
      await callCommand("store_auth_token_secure", { token: "demo-token" });
      setTokenStatus("Token stored in memory.");
    } catch (err) {
      setError(formatError(err));
      setTokenStatus("Failed to update token.");
    }
  };

  const handleSignIn = async () => {
    setError(null);
    setAuthStatus("Signing in...");
    try {
      await signInWithEmailAndPassword(auth, email, password);
      setAuthStatus("Signed in.");
    } catch (err) {
      setAuthStatus("Sign-in failed.");
      setError(formatError(err));
    }
  };

  const handleSignUp = async () => {
    setError(null);
    setAuthStatus("Creating account...");
    try {
      await createUserWithEmailAndPassword(auth, email, password);
      setAuthStatus("Signed in.");
    } catch (err) {
      setAuthStatus("Sign-up failed.");
      setError(formatError(err));
    }
  };

  const handleSignOut = async () => {
    setError(null);
    try {
      await signOut(auth);
      setAuthStatus("Signed out.");
      setTokenStatus("No token");
      setIsAuthenticated(false);
      workerRestartedAfterAuth.current = false;
      workerRestartInProgress.current = false;
      setIngestResults(null);
      setPanelEntries([]);
      if (isTauriEnv) {
        await callCommand("clear_auth_token_secure");
      }
    } catch (err) {
      setError(formatError(err));
    }
  };

  const addPaths = (paths: string[]) => {
    setSelectedPaths((prev) => {
      const merged = new Set(prev);
      for (const path of paths) {
        merged.add(path);
      }
      return Array.from(merged);
    });
  };

  const handleChooseFiles = async () => {
    setError(null);
    if (!isTauriEnv) {
      setError("Choose Files is only available in the desktop app.");
      return;
    }
    try {
      const selected = await open({
        multiple: true,
        title: "Select files to ingest"
      });
      if (!selected) {
        return;
      }
      const paths = Array.isArray(selected) ? selected : [selected];
      const normalized = normalizePathsWithValidation(paths.filter(Boolean));
      if ("error" in normalized) {
        setError(normalized.error);
        return;
      }
      addPaths(normalized.paths);
    } catch (err) {
      setError(formatError(err));
    }
  };

  const handleClearFiles = () => {
    setSelectedPaths([]);
    setFilePaths("");
  };

  const isImagePath = useCallback((path: string) => /\.(png|jpe?g|webp)$/i.test(path), []);
  const isVideoPath = useCallback((path: string) => /\.(mp4|mov|webm|mkv|avi)$/i.test(path), []);

  const normalizeFsPathForTauri = useCallback((path: string) => {
    // `convertFileSrc()` expects a platform-native path.
    // On Windows, normalize any accidental forward slashes back to `\`.
    if (/^[a-zA-Z]:[\\/]/.test(path) || path.startsWith("\\\\")) {
      return path.replace(/\//g, "\\");
    }
    return path;
  }, []);

  const revokeStoryboardObjectUrl = useCallback(() => {
    if (storyboardObjectUrl.current) {
      URL.revokeObjectURL(storyboardObjectUrl.current);
      storyboardObjectUrl.current = null;
    }
  }, []);

  const resetStoryboardSelection = useCallback(
    (clearNotes = false) => {
      revokeStoryboardObjectUrl();
      setStoryboardPath(null);
      setStoryboardUrl(null);
      setStoryboardWidth(0);
      setStoryboardHeight(0);
      setPanelEntries([]);
      setPreparedBoxes(null);
      setStoryboardWarnings([]);
      setStoryboardError(null);
      setStoryboardStatus("Idle");
      if (clearNotes) {
        setStoryboardNotes("");
      }
    },
    [revokeStoryboardObjectUrl]
  );

  useEffect(() => {
    return () => {
      revokeStoryboardObjectUrl();
    };
  }, [revokeStoryboardObjectUrl]);

  const loadStoryboardPreviewUrl = useCallback(
    async (path: string) => {
      revokeStoryboardObjectUrl();

      // In dev mode the UI origin is typically http://localhost and convertFileSrc
      // returns an asset-protocol URL (different origin), which taints canvas.
      // Loading bytes into a blob URL avoids that.
      try {
        const bytes = await readFile(path);
        const lower = path.toLowerCase();
        const mime = lower.endsWith(".png")
          ? "image/png"
          : lower.endsWith(".jpg") || lower.endsWith(".jpeg")
            ? "image/jpeg"
            : lower.endsWith(".webp")
              ? "image/webp"
              : "application/octet-stream";

        const url = URL.createObjectURL(new Blob([bytes], { type: mime }));
        storyboardObjectUrl.current = url;
        return url;
      } catch {
        return convertFileSrc(normalizeFsPathForTauri(path));
      }
    },
    [normalizeFsPathForTauri, revokeStoryboardObjectUrl]
  );

  const defaultItemKindForPath = useCallback(
    (path: string) => {
      if (isImagePath(path)) {
        return "image";
      }
      if (isVideoPath(path)) {
        return "video";
      }
      if (/\.(mp3|wav|m4a|aac|flac|ogg)$/i.test(path)) {
        return "audio";
      }
      return "file";
    },
    [isImagePath, isVideoPath]
  );

  const defaultItemNameForPath = useCallback((path: string) => {
    const base = path.split(/[\\/]/).pop() || path;
    const trimmedBase = base.trim();
    return trimmedBase.replace(/\.[^.]+$/, "");
  }, []);

  useEffect(() => {
    // Ensure per-file settings exist for selected paths.
    setFileItemSettings((prev) => {
      const next: Record<string, FileItemSettings> = {};
      for (const path of selectedPaths) {
        const existing = prev[path];
        next[path] = existing ?? {
          name: defaultItemNameForPath(path),
          kind: defaultItemKindForPath(path)
        };
      }
      return next;
    });
  }, [defaultItemKindForPath, defaultItemNameForPath, selectedPaths]);

  const runIngest = async (paths: string[]) => {
    const files = paths.map((path) => {
      const entry: Record<string, string> = { path };
      if (multiFileMode === "per_file") {
        const settings = fileItemSettings[path];
        entry.name = (settings?.name || defaultItemNameForPath(path)).trim();
        entry.kind = (settings?.kind || defaultItemKindForPath(path)).trim();
      } else if (itemName && paths.length === 1) {
        entry.name = itemName;
      }
      return entry;
    });
    const payload = {
      project_name: projectName,
      space_name: spaceName,
      space_parent_path: subSpacePath || undefined,
      item_kind: itemKind || "file",
      multi_file_mode: multiFileMode,
      item_name: multiFileMode === "single_item" ? itemName || undefined : undefined,
      files,
      move_files: moveFiles,
      move_root: moveFiles ? moveRoot : undefined
    };
    return callCommand<IngestResponse>("ingest_files", { payload });
  };

  const handleIngest = async () => {
    setError(null);
    if (!isAuthenticated) {
      setIngestStatus("Sign in to ingest files.");
      return;
    }
    await refreshAuthToken(true);
    setIngestResults(null);
    setIngestStatus("Sending ingest request...");
    appendLog("info", "Starting ingest...");
    try {
      const manualPaths = filePaths
        .split("\n")
        .map((value) => value.trim())
        .filter(Boolean);
      const allPaths = Array.from(new Set([...selectedPaths, ...manualPaths]));
      for (const path of allPaths) {
        const validationError = validateLocalPath(path);
        if (validationError) {
          setIngestStatus("Provide valid file paths.");
          setError(validationError);
          return;
        }
      }
      if (!allPaths.length) {
        setIngestStatus("Provide at least one file path.");
        return;
      }
      if (allPaths.length > 1 && multiFileMode === "single_item" && !itemName.trim()) {
        setIngestStatus("Provide an item name for multi-file single-item ingest.");
        return;
      }
      if (itemName && allPaths.length > 1 && multiFileMode === "per_file") {
        appendLog("warn", "Item name override is ignored in per-file mode.");
      }
      setIngestBusy(true);

      // Scroll to top of the ingest section to show loading overlay
      document.getElementById("ingest")?.scrollIntoView({ behavior: "smooth", block: "start" });

      // Allow React to render the loading overlay before starting heavy work
      await new Promise(resolve => setTimeout(resolve, 50));

      addOption(projectName, setProjectOptions);
      addOption(spaceName, setSpaceOptions);
      addOption(itemKind || "file", setItemKindOptions);
      const response = await runIngest(allPaths);
      setIngestResults(response);
      if (response.errors.length) {
        setIngestStatus(
          `Ingest partial: ${response.count} succeeded, ${response.errors.length} failed.`
        );
        appendLog(
          "warn",
          `Ingest completed with ${response.errors.length} errors.`
        );
      } else {
        setIngestStatus("Ingest complete.");
        appendLog("info", `Ingested ${response.count} files.`);
        setSelectedPaths([]);
        setFilePaths("");
        setFileItemSettings({});
        setDropStatus("Drop files here");
        if (multiFileMode === "single_item") {
          setItemName("");
        }
      }
    } catch (err) {
      setIngestStatus("Ingest failed.");
      setError(formatError(err));
      appendLog("error", `Ingest failed: ${formatError(err)}`);
    } finally {
      setIngestBusy(false);
    }
  };

  const handleRetryFailed = async () => {
    if (!ingestResults || !ingestResults.errors.length) {
      return;
    }
    setError(null);
    setIngestStatus("Retrying failed files...");
    try {
      const retryPaths = ingestResults.errors
        .map((error) => error.path)
        .filter((path): path is string => Boolean(path));
      if (!retryPaths.length) {
        setIngestStatus("No failed paths to retry.");
        return;
      }
      setIngestBusy(true);
      const response = await runIngest(retryPaths);
      const merged = new Map<string, IngestResult>();
      for (const result of ingestResults.results) {
        merged.set(result.artifact_path ?? result.path, result);
      }
      for (const result of response.results) {
        merged.set(result.artifact_path ?? result.path, result);
      }
      setIngestResults({
        ok: response.errors.length === 0,
        count: merged.size,
        results: Array.from(merged.values()),
        errors: response.errors
      });
      if (response.errors.length) {
        setIngestStatus(
          `Retry partial: ${response.count} succeeded, ${response.errors.length} failed.`
        );
      } else {
        setIngestStatus("Retry complete.");
      }
    } catch (err) {
      setIngestStatus("Retry failed.");
      setError(formatError(err));
    } finally {
      setIngestBusy(false);
    }
  };

  useEffect(() => {
    const unsubscribe = onIdTokenChanged(auth, async (user) => {
      if (!user) {
        setTokenStatus("No token");
        setAuthStatus("Signed out");
        setIsAuthenticated(false);
        workerRestartedAfterAuth.current = false;
        workerRestartInProgress.current = false;
        setIngestResults(null);
        setPanelEntries([]);
        if (isTauriEnv) {
          try {
            await callCommand("clear_auth_token_secure");
          } catch (err) {
            setError(formatError(err));
          }
        }
        return;
      }
      setAuthStatus(`Signed in as ${user.email ?? "user"}`);
      setIsAuthenticated(true);
      try {
        const token = await user.getIdToken();
        setTokenStatus("Token ready.");
        if (isTauriEnv) {
          await callCommand("set_auth_token", { token });
          await callCommand("store_auth_token_secure", { token });

          if (!workerRestartedAfterAuth.current) {
            if (workerRestartInProgress.current) {
              return;
            }
            workerRestartInProgress.current = true;
            setWorkerStatus("Refreshing after auth...");
            appendLog("info", "Restarting Python worker after auth...");
            try {
              await callCommand("restart_python_worker");
              workerRestartedAfterAuth.current = true;
              setWorkerStatus("Running (refreshed after auth)");
              appendLog("info", "Python worker restarted after auth.");

              // Re-query browse data now that the worker is refreshed.
              await refreshProjects();
            } catch (err) {
              workerRestartedAfterAuth.current = false;
              setWorkerStatus("Refresh after auth failed.");
              appendLog("warn", `Worker restart after auth failed: ${formatError(err)}`);

              // Best-effort: still try to refresh browse data if the worker is usable.
              try {
                await refreshProjects();
              } catch {
                // Ignore follow-on failures; primary error already logged.
              }
            } finally {
              workerRestartInProgress.current = false;
            }
          }
        }
      } catch (err) {
        setTokenStatus("Token refresh failed.");
        setError(formatError(err));
      }
    });

    const refreshInterval = window.setInterval(async () => {
      const currentUser = auth.currentUser;
      if (!currentUser) {
        return;
      }
      try {
        const token = await currentUser.getIdToken(true);
        if (isTauriEnv) {
          await callCommand("set_auth_token", { token });
          await callCommand("store_auth_token_secure", { token });
        }
        setTokenStatus("Token refreshed.");
      } catch (err) {
        setTokenStatus("Token refresh failed.");
        setError(formatError(err));
      }
    }, 45 * 60 * 1000);

    return () => {
      unsubscribe();
      window.clearInterval(refreshInterval);
    };
  }, [isTauriEnv]);

  useEffect(() => {
    if (!isTauriEnv) {
      return;
    }
    callCommand<string | null>("load_auth_token_secure")
      .then((token) => {
        if (token) {
          setTokenStatus("Loaded token from keychain.");
          return callCommand("set_auth_token", { token });
        }
        return null;
      })
      .catch((err) => {
        setError(formatError(err));
      });
  }, [isTauriEnv]);

  useEffect(() => {
    if (!isTauriEnv || !isAuthenticated || workerAutoStart.current) {
      return;
    }
    workerAutoStart.current = true;
    setWorkerStatus("Starting...");
    appendLog("info", "Auto-starting Python worker...");
    callCommand("start_python_worker")
      .then(() => {
        setWorkerStatus("Running (stdio JSON-RPC placeholder)");
        appendLog("info", "Python worker auto-started.");
      })
      .catch((err) => {
        setWorkerStatus("Auto-start failed.");
        setError(formatError(err));
        appendLog("error", `Worker auto-start failed: ${formatError(err)}`);
      });
  }, [appendLog, isAuthenticated, isTauriEnv]);

  useEffect(() => {
    if (!isTauriEnv) {
      return;
    }
    let unlisten: (() => void) | undefined;
    getCurrentWindow()
      .onDragDropEvent((event) => {
        const payload = event.payload;
        if (payload.type === "drop") {
          const paths = payload.paths ?? [];
          const imagePaths = paths.filter((path) => /\\.(png|jpe?g|webp)$/i.test(path));
          if (activeView === "storyboard" && imagePaths.length) {
            if (imagePaths.length > 1) {
              setError("Please drop a single contact sheet image.");
              setStoryboardStatus("Drop a single contact sheet.");
              return;
            }
            const selected = imagePaths[0];
            const validationError = validateLocalPath(selected);
            if (validationError) {
              setStoryboardError(validationError);
              setStoryboardStatus("Drop a single contact sheet.");
              return;
            }
            loadStoryboardPreviewUrl(selected)
              .then((previewUrl) => {
                setStoryboardPath(selected);
                setStoryboardUrl(previewUrl);
                setPanelEntries([]);
                setPreparedBoxes(null);
                setStoryboardStatus("Contact sheet loaded.");
              })
              .catch((err) => {
                setStoryboardError(formatError(err));
              });
          } else {
          const normalized = normalizePathsWithValidation(paths);
          if ("error" in normalized) {
            setError(normalized.error);
            setDropStatus("Some files were skipped due to invalid paths.");
            return;
          }
          addPaths(normalized.paths);
            setDropStatus(`Added ${normalized.paths.length} files.`);
          }
        } else if (payload.type === "enter" || payload.type === "over") {
          if (activeView === "storyboard") {
            setStoryboardStatus("Release to set contact sheet.");
          } else {
            setDropStatus("Release to add files.");
          }
        } else if (payload.type === "leave") {
          if (activeView === "storyboard") {
            setStoryboardStatus("Idle");
          } else {
            setDropStatus("Drop files here");
          }
        }
      })
      .then((unsubscribe) => {
        unlisten = unsubscribe;
      });

    return () => {
      if (unlisten) {
        unlisten();
      }
    };
  }, [activeView, isTauriEnv]);


  return (
    <div className="app" data-theme={theme}>
      <header className="app-header">
        <div className="header-left">
          <div className="logo-row">
            <img
              src={theme === "dark" ? logoWhite : logoBlack}
              alt="Kumiho"
              className="logo"
            />
          </div>
          <p className="eyebrow">Ingest Studio</p>
          <p className="subhead">
            Kumiho tracks every revision and the &quot;what-made-this&quot; lineage behind
            your work while your assets stay on your local disk, NAS, or existing storage.
          </p>
        </div>
        <div className="header-right">
          <nav className="nav-tabs" aria-label="Primary">
            <button
              type="button"
              className={activeView === "ingest" ? "active" : ""}
              onClick={() => setActiveView("ingest")}
            >
              Ingest
            </button>
            <button
              type="button"
              className={activeView === "storyboard" ? "active" : ""}
              onClick={() => setActiveView("storyboard")}
            >
              Storyboard Ingest
            </button>
            <button
              type="button"
              className={`icon-button ${activeView === "settings" ? "active" : ""}`}
              onClick={() => setActiveView("settings")}
              aria-label="Settings"
              aria-pressed={activeView === "settings"}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true" fill="none">
                <circle cx="12" cy="12" r="3" />
                <path d="M12 1v3m0 16v3M5.64 5.64l2.12 2.12m8.48 8.48l2.12 2.12M1 12h3m16 0h3M5.64 18.36l2.12-2.12m8.48-8.48l2.12-2.12" />
              </svg>
              <span className="sr-only">Settings</span>
            </button>
          </nav>
          <div className="header-meta">
            <div className="auth-chip">
              <span className="auth-label">Auth</span>
              <span>{authStatus}</span>
            </div>
            {isAuthenticated ? (
              <button className="ghost" onClick={handleSignOut}>
                Sign Out
              </button>
            ) : null}
          </div>
        </div>
      </header>

      <main className="content">
      {error && (
        <section className="section">
          <div className="section-grid section-grid--single">
            <article className="card">
              <p className="error">Error: {error}</p>
            </article>
          </div>
        </section>
      )}
      {!isAuthenticated && activeView !== "settings" ? (
        <section id="login" className="section">
            <div className="section-title">
              <h2>Login</h2>
              <p className="muted">Sign in to continue to settings.</p>
            </div>
            <div className="section-grid section-grid--single">
              <article className="card card--wide">
                <h3>Firebase Auth</h3>
                <div className="auth-form">
                  <input
                    type="email"
                    placeholder="Email"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                  />
                  <input
                    type="password"
                    placeholder="Password"
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                  />
                  <div className="auth-actions">
                    <button onClick={handleSignIn}>Sign In</button>
                    <button className="ghost" onClick={handleSignUp}>
                      Sign Up
                    </button>
                  </div>
                </div>
                <p className="status">{authStatus}</p>
                <p className="status">{tokenStatus}</p>
              </article>
            </div>
          </section>
        ) : null}

        {activeView === "settings" ? (
            <section id="settings" className="section">
            <div className="section-title">
              <h2>Settings</h2>
              <p className="muted">Python environment and worker control.</p>
            </div>
            <div className="section-grid section-grid--stack">
              <article className="card">
                <h3>Appearance</h3>
                <p className="muted">Switch between light and dark themes.</p>
                <div className="theme-toggle">
                  <button
                    type="button"
                    className={theme === "dark" ? "active" : ""}
                    onClick={() => setTheme("dark")}
                    aria-pressed={theme === "dark"}
                  >
                    Dark
                  </button>
                  <button
                    type="button"
                    className={theme === "light" ? "active" : ""}
                    onClick={() => setTheme("light")}
                    aria-pressed={theme === "light"}
                  >
                    Light
                  </button>
                </div>
              </article>
              <article className="card">
                <h3>Python Environment</h3>
          <p className="muted">
            Ensure the local venv exists and the kumiho SDK is installed.
          </p>
          <div className="rows">
            <div>
              <span>App data</span>
              <strong>{envInfo.app_data_dir}</strong>
            </div>
            <div>
              <span>Venv</span>
              <strong>{envInfo.venv_dir}</strong>
            </div>
            <div>
              <span>Python</span>
              <strong>{envInfo.python_path}</strong>
            </div>
          </div>
          <button onClick={handleEnsureEnv}>Ensure Python Env</button>
          <button className="ghost" onClick={handleUpdateSdk}>
            Update SDK
          </button>
          <p className="status">{envStatus}</p>
          <p className="status">{sdkStatus}</p>
        </article>

        <article className="card">
          <h3>Server</h3>
          <p className="muted">
            Connect to a self-hosted Kumiho server (Community Edition) instead of
            Kumiho Cloud. CE serves plaintext gRPC on loopback and needs no sign-in.
          </p>
          <label className="checkbox-row" style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <input
              type="checkbox"
              checked={localServerEnabled}
              onChange={(event) => setLocalServerEnabled(event.target.checked)}
            />
            <span>Use local server (CE)</span>
          </label>
          {localServerEnabled ? (
            <input
              type="text"
              value={localServerAddr}
              onChange={(event) => setLocalServerAddr(event.target.value)}
              placeholder="127.0.0.1:9190"
              style={{ marginTop: 8 }}
            />
          ) : null}
          <button onClick={handleSaveLocalServer}>Apply &amp; restart worker</button>
          <p className="status">{localServerStatus}</p>
        </article>

        <article className="card">
          <h3>Worker Control</h3>
          <p className="muted">
            Auto-starts the long-running Python worker over stdio JSON-RPC.
          </p>
          <button onClick={handleStartWorker}>Start Worker</button>
          <p className="status">{workerStatus}</p>
        </article>
        <article className="card">
          <h3>Auth Status</h3>
          <p className="muted">Token refresh stays in the UI and is passed to the worker.</p>
          <p className="status">{authStatus}</p>
          <p className="status">{tokenStatus}</p>
          <button className="ghost" onClick={handleSetToken} disabled={!isAuthenticated}>
            Send Demo Token
          </button>
        </article>
        <article className="card">
          <h3>Logs</h3>
          <div className="log-actions">
            <button className="ghost" onClick={() => setLogs([])}>
              Clear
            </button>
          </div>
          <div className="log-list">
            {logs.length ? (
              logs.map((entry) => (
                <div
                  key={entry.id}
                  className={`log-entry log-entry--${entry.level}`}
                >
                  <span className="log-meta">
                    [{entry.timestamp}] {entry.source}
                  </span>
                  <span className="log-message">{entry.message}</span>
                </div>
              ))
            ) : (
              <p className="muted">No logs yet.</p>
            )}
          </div>
        </article>
      </div>
    </section>
          ) : null}

    {isAuthenticated && activeView === "storyboard" ? (
      <section id="storyboard" className="section">
      <div className="section-title">
        <h2>Storyboard Ingest</h2>
        <p className="muted">Slice contact sheets and build sequences.</p>
      </div>
      <div className="section-grid section-grid--single">
        <article className="card card--wide" style={{ position: 'relative' }}>
          {storyboardBusy ? (
            <div className="loading-overlay">
              <div className="loading-spinner-large" />
              <p className="loading-text">{storyboardStatus}</p>
            </div>
          ) : null}
          <h3>Storyboard Ingest</h3>
          <p className="muted">
            Contact-sheet slicing and bundle sequencing will live here.
          </p>
          {!isAuthenticated ? (
            <p className="callout">Sign in to ingest storyboards.</p>
          ) : null}
          <div
            className="storyboard-grid"
            onMouseEnter={() => setActiveDropTarget("storyboard")}
            onMouseLeave={() => setActiveDropTarget("ingest")}
          >
            <div className="storyboard-controls">
              <div className="drop-zone">
                <strong>Drag &amp; Drop</strong>
                <p>
                  {storyboardStatus === "Idle"
                    ? "Drop a single contact sheet image here"
                    : storyboardStatus}
                </p>
                <div className="drop-actions">
                  <button onClick={handleChooseStoryboard}>Choose Storyboard image</button>
                  <button
                    className="ghost"
                    onClick={handleClearStoryboard}
                    disabled={!storyboardPath}
                  >
                    Clear
                  </button>
                </div>
              </div>
              {storyboardPath ? <p className="muted">{storyboardPath}</p> : null}

              <div className="ingest-bar">
                <label>
                  Project
                  <input
                    type="text"
                    list="project-options-storyboard"
                    placeholder="project"
                    value={projectName}
                    onChange={(event) => setProjectName(event.target.value)}
                    onBlur={() => addOption(projectName, setProjectOptions)}
                    disabled={!isAuthenticated}
                  />
                </label>
                {spaceLevelOptions.map((level, index) => {
                  const currentPath = spaceHierarchy[index] ?? "";
                  const currentValue = currentPath ? spaceLastSegment(currentPath) : "";
                  const datalistId = `space-level-storyboard-${index}-options`;
                  return (
                    <label key={datalistId}>
                      {level.label}
                      <input
                        type="text"
                        list={datalistId}
                        placeholder={index === 0 ? "scene" : "Sub-folder"}
                        value={currentValue}
                        onChange={(event) => handleSpaceLevelChange(index, event.target.value)}
                        onBlur={() => {
                          if (index === 0) {
                            addOption(currentValue, setSpaceOptions);
                          }
                        }}
                        disabled={!isAuthenticated}
                      />
                      <datalist id={datalistId}>
                        {level.options.map((option) => (
                          <option key={option} value={option} />
                        ))}
                      </datalist>
                    </label>
                  );
                })}
              </div>
              <datalist id="project-options-storyboard">
                {projectOptions.map((option) => (
                  <option key={option} value={option} />
                ))}
              </datalist>
              <div className="item-grid" style={{ gridTemplateColumns: "1fr" }}>
                <label>
                  Storyboard description
                  <textarea
                    value={storyboardNotes}
                    onChange={(event) => setStoryboardNotes(event.target.value)}
                    placeholder="Paste storyboard notes (one block per shot)"
                    rows={6}
                  />
                </label>
              </div>
              <div className="item-grid">
                <label>
                  Bundle tag
                  <input
                    type="text"
                    value={bundleTag}
                    onChange={(event) => setBundleTag(event.target.value)}
                    placeholder="ingested"
                    disabled={!isAuthenticated}
                  />
                </label>
              </div>
              <div className="number-row">
                <label>
                  Rows
                  <input
                    type="number"
                    min="1"
                    max="20"
                    value={gridRows}
                    onChange={(event) => setGridRows(Number(event.target.value))}
                  />
                </label>
                <label>
                  Columns
                  <input
                    type="number"
                    min="1"
                    max="20"
                    value={gridCols}
                    onChange={(event) => setGridCols(Number(event.target.value))}
                  />
                </label>
                <label>
                  Margin
                  <input
                    type="number"
                    value={marginPx}
                    onChange={(event) => setMarginPx(Number(event.target.value))}
                  />
                </label>
                <label>
                  Gutter
                  <input
                    type="number"
                    value={gutterPx}
                    onChange={(event) => setGutterPx(Number(event.target.value))}
                  />
                </label>
                <label>
                  Offset X
                  <input
                    type="number"
                    value={offsetX}
                    onChange={(event) => setOffsetX(Number(event.target.value))}
                  />
                </label>
                <label>
                  Offset Y
                  <input
                    type="number"
                    value={offsetY}
                    onChange={(event) => setOffsetY(Number(event.target.value))}
                  />
                </label>
              </div>
              <label className="checkbox">
                <input
                  type="checkbox"
                  checked={moveFiles}
                  onChange={(event) => setMoveFiles(event.target.checked)}
                />
                Move files into structured storage
              </label>
              {moveFiles ? (
                <input
                  type="text"
                  placeholder="Move root folder (e.g. D:\\KumihoStorage)"
                  value={moveRoot}
                  onChange={(event) => setMoveRoot(event.target.value)}
                />
              ) : null}
              <button
                onClick={() => void handleCutAndPrep()}
                disabled={!storyboardPath || !storyboardUrl}
              >
                Cut &amp; Prep
              </button>
            </div>
            <div
              className="storyboard-preview"
            >
              {storyboardUrl ? (
                <div className="preview-frame">
                  <img
                    ref={imageRef}
                    src={storyboardUrl}
                    alt="Storyboard contact sheet"
                    onError={() => {
                      setStoryboardStatus("Failed to load contact sheet preview.");
                      setStoryboardError(
                        "Failed to load contact sheet preview. Check the file path and Tauri asset protocol permissions."
                      );
                    }}
                    onLoad={(event) => {
                      const img = event.currentTarget;
                      const width = img.naturalWidth;
                      const height = img.naturalHeight;
                      setStoryboardWidth(width);
                      setStoryboardHeight(height);
                    }}
                  />
                  <div className="overlay">
                    {(panelEntries.length && preparedBoxes ? preparedBoxes : sliceResult.boxes).map(
                      (box, index) => {
                        const img = imageRef.current;
                        const scaleX = img && storyboardWidth ? img.clientWidth / storyboardWidth : 1;
                        const scaleY = img && storyboardHeight ? img.clientHeight / storyboardHeight : scaleX;
                      return (
                        <div
                          key={`${box.x}-${box.y}-${index}`}
                          className="overlay-box"
                          style={{
                            left: box.x * scaleX,
                            top: box.y * scaleY,
                            width: box.width * scaleX,
                            height: box.height * scaleY
                          }}
                        />
                      );
                      }
                    )}
                  </div>
                </div>
              ) : (
                <div className="preview-placeholder">
                  Select a contact sheet to preview slicing.
                </div>
              )}
            </div>
          </div>
          {storyboardError ? (
            <p className="error">Error: {storyboardError}</p>
          ) : null}
          {storyboardUrl && storyboardWarnings.length ? (
            <div className="warning">
              {storyboardWarnings.map((warning) => (
                <p key={warning}>{warning}</p>
              ))}
            </div>
          ) : null}
          {panelEntries.length ? (
            <div
              className="sequence-grid"
              style={{ "--panel-aspect": panelAspect, "--panel-cols": gridCols } as CSSProperties}
            >
              {panelEntries.map((panel, index) => {
                const preview = isTauriEnv
                  ? convertFileSrc(normalizeFsPathForTauri(panel.path))
                  : "";
                const shotIndex = panel.index ?? index;
                const fallbackCode = String(shotIndex + 1).padStart(3, "0");
                const shotCode = (panel.name ?? "").trim() || fallbackCode;
                return (
                  <div
                    key={panel.path}
                    className="sequence-card"
                  >
                    <div className="thumb panel-thumb">
                      {preview ? <img src={preview} alt={`Panel ${index + 1}`} /> : null}
                    </div>
                    <div className="sequence-meta">
                      <span className="index">Shot Code: {shotCode}</span>
                      <div className="item-grid item-grid--stack">
                        <label>
                          Shot Code
                          <input
                            type="text"
                            value={panel.name ?? ""}
                            placeholder={fallbackCode}
                            onChange={(event) => {
                              const value = event.target.value;
                              setPanelEntries((prev) =>
                                prev.map((entry, entryIndex) =>
                                  entryIndex === index ? { ...entry, name: value } : entry
                                )
                              );
                            }}
                            onBlur={(event) => {
                              if (event.target.value.trim()) {
                                return;
                              }
                              setPanelEntries((prev) =>
                                prev.map((entry, entryIndex) =>
                                  entryIndex === index ? { ...entry, name: fallbackCode } : entry
                                )
                              );
                            }}
                          />
                        </label>
                        <label>
                          Shot Type
                          <select
                            value={panel.shotType ?? ""}
                            onChange={(event) => {
                              const value = event.target.value;
                              setPanelEntries((prev) =>
                                prev.map((entry, entryIndex) =>
                                  entryIndex === index ? { ...entry, shotType: value } : entry
                                )
                              );
                            }}
                          >
                            <option value="">(select)</option>
                            {SHOT_TYPE_OPTIONS.map((option) => (
                              <option key={option.value} value={option.value}>
                                {option.label}
                              </option>
                            ))}
                          </select>
                        </label>
                        <label>
                          Camera Angle
                          <select
                            value={panel.cameraAngle ?? ""}
                            onChange={(event) => {
                              const value = event.target.value;
                              setPanelEntries((prev) =>
                                prev.map((entry, entryIndex) =>
                                  entryIndex === index ? { ...entry, cameraAngle: value } : entry
                                )
                              );
                            }}
                          >
                            <option value="">(select)</option>
                            {CAMERA_ANGLE_OPTIONS.map((option) => (
                              <option key={option.value} value={option.value}>
                                {option.label}
                              </option>
                            ))}
                          </select>
                        </label>
                        <label>
                          Camera Move
                          <select
                            value={panel.cameraMove ?? ""}
                            onChange={(event) => {
                              const value = event.target.value;
                              setPanelEntries((prev) =>
                                prev.map((entry, entryIndex) =>
                                  entryIndex === index ? { ...entry, cameraMove: value } : entry
                                )
                              );
                            }}
                          >
                            <option value="">(select)</option>
                            {CAMERA_MOVE_OPTIONS.map((option) => (
                              <option key={option.value} value={option.value}>
                                {option.label}
                              </option>
                            ))}
                          </select>
                        </label>
                      </div>
                      <div className="item-grid" style={{ gridTemplateColumns: "1fr" }}>
                        <label>
                          Description
                          <textarea
                            value={panel.description ?? ""}
                            onChange={(event) => {
                              const value = event.target.value;
                              setPanelEntries((prev) =>
                                prev.map((entry, entryIndex) =>
                                  entryIndex === index ? { ...entry, description: value } : entry
                                )
                              );
                            }}
                            rows={4}
                            style={{ minHeight: 120 }}
                          />
                        </label>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          ) : null}
          {panelEntries.length ? (
            <div className="sequence-actions-row">
              <span className="status sequence-status">
                {storyboardStatus !== "Idle" && !storyboardBusy ? storyboardStatus : ""}
              </span>
              <button onClick={handleIngestAndBundle} disabled={!storyboardCanIngest || storyboardBusy}>
                Ingest &amp; Bundle
              </button>
            </div>
          ) : null}
          {storyboardResults ? (
            <div className="ingest-results">
              <h4>Storyboard Results</h4>
              <p className="status">
                Bundle kref: {storyboardResults.bundleKref ?? "?"}
              </p>
              <h5>Bundle members</h5>
              {storyboardResults.memberItemKrefs.length ? (
                <ul className="result-list ingest-results-list">
                  {storyboardResults.memberItemKrefs.map((kref) => (
                    <li key={kref}>
                      <p className="path">{kref}</p>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="muted">No bundle members reported.</p>
              )}
              <h5>Artifact krefs</h5>
              {storyboardResults.artifactKrefs.length ? (
                <ul className="result-list ingest-results-list">
                  {storyboardResults.artifactKrefs.map((kref) => (
                    <li key={kref}>
                      <p className="path">{kref}</p>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="muted">No artifact krefs reported.</p>
              )}
            </div>
          ) : null}
        </article>
      </div>
    </section>
    ) : null}

    {isAuthenticated && activeView === "ingest" ? (
      <section id="ingest" className="section">
      <div className="section-title">
        <h2>Ingest</h2>
        <p className="muted">Register local file paths only.</p>
      </div>
      <div className="section-grid section-grid--single">
        <article className="card card--wide" style={{ position: 'relative' }}>
          {ingestBusy ? (
            <div className="loading-overlay">
              <div className="loading-spinner-large" />
              <p className="loading-text">{ingestStatus}</p>
            </div>
          ) : null}
          <h3>Ingest Files</h3>
          <p className="muted">
            Provide local file paths. The worker only registers paths and never
            uploads bytes.
          </p>
          {!isAuthenticated ? <p className="callout">Sign in to ingest files.</p> : null}
          <div className="ingest-bar">
            <label>
              Project
              <input
                type="text"
                list="project-options"
                placeholder="project"
                value={projectName}
                onChange={(event) => setProjectName(event.target.value)}
                onBlur={() => addOption(projectName, setProjectOptions)}
                disabled={!isAuthenticated}
              />
            </label>
            {spaceLevelOptions.map((level, index) => {
              const currentPath = spaceHierarchy[index] ?? "";
              const currentValue = currentPath ? spaceLastSegment(currentPath) : "";
              const datalistId = `space-level-${index}-options`;
              return (
                <label key={datalistId}>
                  {level.label}
                  <input
                    type="text"
                    list={datalistId}
                    placeholder={index === 0 ? "scene" : "Sub-folder"}
                    value={currentValue}
                    onChange={(event) => handleSpaceLevelChange(index, event.target.value)}
                    onBlur={() => {
                      if (index === 0) {
                        addOption(currentValue, setSpaceOptions);
                      }
                    }}
                    disabled={!isAuthenticated}
                  />
                  <datalist id={datalistId}>
                    {level.options.map((option) => (
                      <option key={option} value={option} />
                    ))}
                  </datalist>
                </label>
              );
            })}
          </div>

          <div className="item-grid" style={{ marginTop: 12 }}>
            <label>
              Multi-file mode
              <select
                value={multiFileMode}
                onChange={(event) =>
                  setMultiFileMode(event.target.value as "per_file" | "single_item")
                }
                disabled={!isAuthenticated}
              >
                <option value="per_file">One item per file (separate revisions)</option>
                <option value="single_item">Single item (many revisions)</option>
              </select>
            </label>
          </div>

          <datalist id="project-options">
            {projectOptions.map((option) => (
              <option key={option} value={option} />
            ))}
          </datalist>
          <div className="item-grid">
            <label>
              Item name
              <input
                type="text"
                placeholder={
                  multiFileMode === "single_item"
                    ? "Required for multi-file single-item ingest"
                    : "Overrides single-file item name"
                }
                value={itemName}
                onChange={(event) => setItemName(event.target.value)}
                disabled={!isAuthenticated || multiFileMode === "per_file"}
              />
            </label>
            <label>
              Item kind
              <input
                type="text"
                list="item-kind-options"
                placeholder="file"
                value={itemKind}
                onChange={(event) => setItemKind(event.target.value)}
                onBlur={() => addOption(itemKind || "file", setItemKindOptions)}
                disabled={!isAuthenticated || multiFileMode === "per_file"}
              />
            </label>
          </div>
          <datalist id="item-kind-options">
            {itemKindOptions.map((option) => (
              <option key={option} value={option} />
            ))}
          </datalist>
          <div
            className="drop-zone"
            onMouseEnter={() => setActiveDropTarget("ingest")}
            onMouseLeave={() => setActiveDropTarget("ingest")}
          >
            <strong>Drag &amp; Drop</strong>
            <p>{dropStatus}</p>
            <button onClick={handleChooseFiles} disabled={!isAuthenticated}>
              Choose Files
            </button>
          </div>
          <div className="ingest-grid">
            <textarea
              placeholder="Paste file paths (one per line)"
              value={filePaths}
              onChange={(event) => setFilePaths(event.target.value)}
              rows={4}
              disabled={!isAuthenticated}
            />
          </div>
          <div className="file-list">
            <div>
              <span>Selected files</span>
              <strong>{selectedPaths.length}</strong>
            </div>
            <button className="ghost" onClick={handleClearFiles}>
              Clear list
            </button>
          </div>
          {selectedPaths.length ? (
            <ul
              className={
                multiFileMode === "per_file"
                  ? "result-list ingest-selected-list"
                  : "paths paths-with-preview"
              }
            >
              {selectedPaths.map((path) => {
                const preview = isTauriEnv
                  ? convertFileSrc(normalizeFsPathForTauri(path))
                  : "";
                const showImage = isImagePath(path);
                const showVideo = isVideoPath(path);
                const settings = fileItemSettings[path];

                if (multiFileMode === "per_file") {
                  return (
                    <li key={path}>
                      <div className="thumb">
                        {preview && showImage ? <img src={preview} alt="Selected preview" /> : null}
                        {preview && !showImage && showVideo ? (
                          <video src={preview} muted playsInline preload="metadata" />
                        ) : null}
                      </div>
                      <div>
                        <p className="path">{path}</p>
                        <div className="item-grid" style={{ marginTop: 8 }}>
                          <label>
                            Item name
                            <input
                              type="text"
                              value={settings?.name ?? defaultItemNameForPath(path)}
                              onChange={(event) => {
                                const nextName = event.target.value;
                                setFileItemSettings((prev) => ({
                                  ...prev,
                                  [path]: {
                                    name: nextName,
                                    kind: prev[path]?.kind ?? defaultItemKindForPath(path)
                                  }
                                }));
                              }}
                              disabled={!isAuthenticated}
                            />
                          </label>
                          <label>
                            Kind
                            <input
                              type="text"
                              list="item-kind-options"
                              value={settings?.kind ?? defaultItemKindForPath(path)}
                              onChange={(event) => {
                                const nextKind = event.target.value;
                                setFileItemSettings((prev) => ({
                                  ...prev,
                                  [path]: {
                                    name: prev[path]?.name ?? defaultItemNameForPath(path),
                                    kind: nextKind
                                  }
                                }));
                              }}
                              onBlur={() =>
                                addOption(
                                  (settings?.kind ?? defaultItemKindForPath(path)) || "file",
                                  setItemKindOptions
                                )
                              }
                              disabled={!isAuthenticated}
                            />
                          </label>
                        </div>
                      </div>
                    </li>
                  );
                }

                return (
                  <li key={path}>
                    <div className="thumb">
                      {preview && showImage ? <img src={preview} alt="Selected preview" /> : null}
                      {preview && !showImage && showVideo ? (
                        <video src={preview} muted playsInline preload="metadata" />
                      ) : null}
                    </div>
                    <p className="path">{path}</p>
                  </li>
                );
              })}
            </ul>
          ) : null}
          <label className="checkbox">
            <input
              type="checkbox"
              checked={moveFiles}
              onChange={(event) => setMoveFiles(event.target.checked)}
              disabled={!isAuthenticated}
            />
            Move files into structured storage
          </label>
          {moveFiles ? (
            <input
              type="text"
              placeholder="Move root folder (e.g. D:\\KumihoStorage)"
              value={moveRoot}
              onChange={(event) => setMoveRoot(event.target.value)}
              disabled={!isAuthenticated}
            />
          ) : null}
          <button onClick={handleIngest} disabled={!isAuthenticated || ingestBusy}>
            Ingest Paths
          </button>
          {ingestResults && ingestResults.errors.length ? (
            <button className="ghost" onClick={handleRetryFailed} disabled={!isAuthenticated || ingestBusy}>
              Retry Failed
            </button>
          ) : null}
          <p className="status">
            {ingestStatus}
            {ingestBusy ? <span className="spinner" aria-hidden="true" /> : null}
          </p>
          {ingestResults ? (
            <div className="ingest-results">
              <h4>Ingest Results</h4>
              {ingestResults.results.length ? (
                <ul className="result-list ingest-results-list">
                  {ingestResults.results.map((result) => {
                    const displayPath = result.artifact_path ?? result.path;
                    return (
                      <li key={`${displayPath}-${result.revision_kref ?? result.item_kref ?? ""}`}>
                        <div>
                          <p className="path">Artifact: {result.artifact_kref ?? "—"}</p>
                          <p className="path">Location: {displayPath}</p>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              ) : null}
              {ingestResults.errors.length ? (
                <div className="error-list">
                  <h5>Failed</h5>
                  <ul>
                    {ingestResults.errors.map((errorItem) => (
                      <li key={`${errorItem.path ?? "missing"}-${errorItem.error}`}>
                        <span>{errorItem.path ?? "unknown path"}</span>
                        <span>{errorItem.error}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              ) : null}
            </div>
          ) : null}
        </article>
      </div>
    </section>
    ) : null}
      </main>

      <footer className="app-footer">
        <div className="footer-status">
          <p className="eyebrow">Live status</p>
          <div className="status-grid">
            <div>
              <span>Python env</span>
              <strong>{envStatus}</strong>
            </div>
            <div>
              <span>Worker</span>
              <strong>{workerStatus}</strong>
            </div>
            <div>
              <span>Auth</span>
              <strong>{authStatus}</strong>
            </div>
            <div>
              <span>Ingest</span>
              <strong>{ingestStatus}</strong>
            </div>
          </div>
        </div>
        <div className="footer-meta">
          <span className="footer-note">{environmentNote}</span>
          <span className="footer-note">{tokenStatus}</span>
        </div>
      </footer>
    </div>
  );
}
