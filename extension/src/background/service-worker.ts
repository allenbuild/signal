import { CommandExecutor } from "./command-executor";
import {
  ExtensionStorage,
  type StoredExtensionState,
} from "./storage";
import {
  ActiveTabRouter,
  isSupportedPageUrl,
  type RoutableTab,
} from "./tab-router";
import { TabZoomController } from "./zoom";
import {
  OFFSCREEN_PORT_NAME,
  PROTECTED_PAGE_MESSAGE,
  isTrackingFrameMessage,
  type ContentActionResultMessage,
  type OffscreenStateMessage,
  type SignalMessage,
  type TrackingFrameMessage,
} from "../shared/messages";
import { CommandGestureEngine } from "../shared/gesture";
import { safeParseSignalCommand } from "../shared/schema";
import {
  DEFAULT_TUNING,
  sanitizeTuning,
} from "../shared/tuning";
import {
  type BrowserCommandAction,
  type CommandPlan,
  type GestureId,
  type SignalCommand,
  type SignalMode,
  type StoredProfile,
} from "../shared/types";
import {
  ACTIVE_COMMAND_GESTURES,
  getActiveCommandDefinition,
  type ActiveCommandGesture,
  type WebsiteAction,
} from "../shared/defaults";

const OFFSCREEN_DOCUMENT = "offscreen/offscreen.html";
const PERMISSION_DOCUMENT = "setup/setup.html";
const SESSION_KEY = "signal.extension.runtime.v1";
const PUBLIC_SITE = "https://signal-hand-control.allenxtech.chatgpt.site";

type CameraState =
  | "off"
  | "starting"
  | "running"
  | "paused"
  | "error"
  | "permission";

type RuntimeState = {
  running: boolean;
  paused: boolean;
  mode: "control" | "commands";
  camera: CameraState;
  fps: number;
  gesture: string | null;
  confidence: number;
  activeTabSupported: boolean;
  status: string;
  commandProgress?: number;
};

type StoredRuntimeSession = {
  running: boolean;
  paused: boolean;
};

const runtimeState: RuntimeState = {
  running: false,
  paused: false,
  mode: "control",
  camera: "off",
  fps: 0,
  gesture: null,
  confidence: 0,
  activeTabSupported: false,
  status: "Start Signal to enable private, on-device tracking.",
};

const storage = new ExtensionStorage({
  local: chrome.storage.local,
  sync: chrome.storage.sync,
});
let storedState: StoredExtensionState | null = null;
let gestureEngine = new CommandGestureEngine();
let editorOpen = false;
let offscreenPort: chrome.runtime.Port | null = null;
let offscreenCreation: Promise<void> | null = null;
let lastTelemetryAt = 0;
let initialization: Promise<void> | null = null;
let demoSessionId: string | null = null;
let demoTabId: number | null = null;
let stopping = false;
let lifecycleQueue: Promise<unknown> = Promise.resolve();
let activeCommand: AbortController | null = null;

function activeMode(): SignalMode {
  return !runtimeState.running || runtimeState.paused
    ? "paused"
    : runtimeState.mode;
}

function enqueueLifecycle<T>(operation: () => Promise<T>): Promise<T> {
  const queued = lifecycleQueue.then(operation, operation);
  lifecycleQueue = queued.catch(() => undefined);
  return queued;
}

function cancelActiveCommand() {
  activeCommand?.abort(new DOMException("Command cancelled.", "AbortError"));
  activeCommand = null;
}

async function getActiveTab(): Promise<chrome.tabs.Tab | null> {
  const tabs = await chrome.tabs.query({
    active: true,
    lastFocusedWindow: true,
  });
  return tabs[0] ?? null;
}

function routable(tab: chrome.tabs.Tab): RoutableTab | null {
  if (tab.id === undefined) return null;
  return {
    id: tab.id,
    url: tab.url,
    active: tab.active,
    windowId: tab.windowId,
    index: tab.index,
  };
}

async function sendTabMessage(tabId: number, message: SignalMessage) {
  return chrome.tabs.sendMessage(tabId, message);
}

const router = new ActiveTabRouter({
  async getActiveTab() {
    const tab = await getActiveTab();
    return tab ? routable(tab) : null;
  },
  sendMessage: sendTabMessage,
  async injectContentScript(tabId) {
    await chrome.scripting.executeScript({
      target: { tabId, allFrames: true },
      files: ["content/content-script.js"],
    });
  },
  onUnsupported(message) {
    void patchRuntime({
      activeTabSupported: false,
      status: message,
    });
  },
});

const zoom = new TabZoomController(
  {
    getZoom: (tabId) => chrome.tabs.getZoom(tabId),
    setZoom: (tabId, factor) => chrome.tabs.setZoom(tabId, factor),
  },
  { rateLimitMs: DEFAULT_TUNING.zoomRateLimitMs },
);

async function sendContentAction(
  tabId: number,
  action: BrowserCommandAction,
  requestId: string,
) {
  const response = (await chrome.tabs.sendMessage(tabId, {
    version: 1,
    type: "signal:content-action",
    requestId,
    action,
  })) as ContentActionResultMessage | undefined;
  return response?.type === "signal:content-action-result"
    ? { ok: response.ok, message: response.message }
    : { ok: false, message: "The page did not accept the reviewed action." };
}

const commandExecutor = new CommandExecutor({
  async getActiveTab() {
    const tab = await getActiveTab();
    return tab?.id === undefined
      ? null
      : {
          id: tab.id,
          windowId: tab.windowId,
          index: tab.index,
          active: tab.active,
        };
  },
  async createTab(options) {
    const tab = await chrome.tabs.create(options);
    if (tab.id === undefined) throw new Error("Chrome did not create the tab.");
    return tab as { id: number };
  },
  async updateTab(tabId, changes) {
    const tab = await chrome.tabs.update(tabId, changes);
    if (!tab || tab.id === undefined) {
      throw new Error("The browser tab is unavailable.");
    }
    return tab as { id: number };
  },
  removeTab: (tabId) => chrome.tabs.remove(tabId),
  async listTabs(windowId) {
    const tabs = await chrome.tabs.query(
      windowId === undefined ? {} : { windowId },
    );
    return tabs
      .filter((tab): tab is chrome.tabs.Tab & { id: number } => tab.id !== undefined)
      .map((tab) => ({
        id: tab.id,
        windowId: tab.windowId,
        index: tab.index,
        active: tab.active,
      }));
  },
  sendContentAction,
  zoom,
  async createNotification(options) {
    const tab = await getActiveTab();
    if (tab?.id === undefined) throw new Error("No active page is available.");
    const receipt = await sendContentAction(
      tab.id,
      {
        type: "show_overlay",
        parameters: {
          title: options.title,
          body: options.message,
          durationMs: 4_000,
        },
      },
      `notification_${crypto.randomUUID()}`,
    );
    if (!receipt.ok) throw new Error(receipt.message);
  },
});

async function hasOffscreenDocument() {
  const contexts = await chrome.runtime.getContexts({
    contextTypes: [chrome.runtime.ContextType.OFFSCREEN_DOCUMENT],
    documentUrls: [chrome.runtime.getURL(OFFSCREEN_DOCUMENT)],
  });
  return contexts.length > 0;
}

async function ensureOffscreenDocument() {
  if (await hasOffscreenDocument()) return;
  if (!offscreenCreation) {
    offscreenCreation = chrome.offscreen
      .createDocument({
        url: OFFSCREEN_DOCUMENT,
        reasons: [chrome.offscreen.Reason.USER_MEDIA],
        justification:
          "Process the user-approved camera locally for cross-tab hand controls.",
      })
      .finally(() => {
        offscreenCreation = null;
      });
  }
  await offscreenCreation;
}

async function closeOffscreenDocument() {
  if (!(await hasOffscreenDocument())) return;
  await chrome.offscreen.closeDocument();
  offscreenPort = null;
}

function waitForOffscreenPort(timeoutMs = 3_000) {
  if (offscreenPort) return Promise.resolve(offscreenPort);
  return new Promise<chrome.runtime.Port>((resolve, reject) => {
    const started = Date.now();
    const timer = setInterval(() => {
      if (offscreenPort) {
        clearInterval(timer);
        resolve(offscreenPort);
      } else if (Date.now() - started >= timeoutMs) {
        clearInterval(timer);
        reject(new Error("Signal’s camera runtime did not connect."));
      }
    }, 25);
  });
}

async function sendOffscreen(
  type:
    | "signal:offscreen/start"
    | "signal:offscreen/pause"
    | "signal:offscreen/stop"
    | "signal:offscreen/ping",
) {
  await ensureOffscreenDocument();
  const port = await waitForOffscreenPort();
  port.postMessage({ version: 1, type });
}

async function persistRuntimeSession() {
  await chrome.storage.session.set({
    [SESSION_KEY]: {
      running: runtimeState.running,
      paused: runtimeState.paused,
    } satisfies StoredRuntimeSession,
  });
}

async function broadcastRuntime() {
  try {
    await chrome.runtime.sendMessage({
      version: 1,
      type: "signal:runtime-state",
      state: { ...runtimeState },
    });
  } catch {
    // The side panel is allowed to be closed.
  }
}

async function patchRuntime(patch: Partial<RuntimeState>, persist = false) {
  Object.assign(runtimeState, patch);
  if (persist) await persistRuntimeSession();
  await broadcastRuntime();
}

async function sendModeToActiveTab() {
  const tabId = router.activeTabId;
  if (tabId === null) return;
  try {
    await chrome.tabs.sendMessage(tabId, {
      version: 1,
      type: "signal:mode",
      mode: activeMode(),
    });
  } catch {
    // The router will inject or retry when the next frame arrives.
  }
}

async function sendTuningToActiveTab() {
  const tabId = router.activeTabId;
  if (tabId === null || !storedState) return;
  try {
    await chrome.tabs.sendMessage(tabId, {
      version: 1,
      type: "signal:tuning",
      tuning: {
        sensitivity: storedState.tuning.pointerSensitivity,
        smoothing: storedState.tuning.pointerSmoothing,
        hideSiteCursor: storedState.settings.hideSiteCursor,
      },
    });
  } catch {
    // The router will inject or retry when the tab becomes available.
  }
}

async function openPermissionSetup() {
  const setupUrl = chrome.runtime.getURL(PERMISSION_DOCUMENT);
  const tabs = await chrome.tabs.query({});
  const existing = tabs.find(
    (tab) => tab.id !== undefined && tab.url?.startsWith(setupUrl),
  );
  if (existing?.id !== undefined) {
    await chrome.tabs.update(existing.id, { active: true });
    return existing;
  }
  return chrome.tabs.create({ url: setupUrl });
}

async function refreshActiveTab(
  reason: "tab-change" | "service-worker-restart" = "tab-change",
) {
  const tab = await getActiveTab();
  const candidate = tab ? routable(tab) : null;
  if (!candidate) {
    await patchRuntime({
      activeTabSupported: false,
      status: "Signal has no active browser tab.",
    });
    return;
  }
  const result = await router.activate(candidate, reason);
  const supported = result.status === "sent";
  await patchRuntime({
    activeTabSupported: supported,
    status: supported
      ? runtimeState.running
        ? `${runtimeState.mode === "control" ? "Control" : "Commands"} mode is active on this tab.`
        : runtimeState.status
      : PROTECTED_PAGE_MESSAGE,
  });
  if (supported) {
    await sendModeToActiveTab();
    await sendTuningToActiveTab();
  }
}

function resetGestureEngine() {
  gestureEngine.reset();
}

function commandPlan(
  id: string,
  name: string,
  action: BrowserCommandAction,
): CommandPlan {
  return {
    schemaVersion: 1,
    id: `plan.${id}`,
    name,
    description: `${name} preset`,
    steps: [
      {
        id: "step-1",
        action,
        timeoutMs: 10_000,
        onFailure: "stop",
        confirmation: { mode: "none", reason: "" },
      },
    ],
    timeoutMs: 13_000,
    onFailure: "stop",
    confirmation: { mode: "none", reason: "" },
    createdSource: "visual",
    secretReferences: [],
  };
}

function presetCommand(gesture: GestureId): SignalCommand | null {
  const definition = getActiveCommandDefinition(gesture);
  if (
    !definition ||
    definition.configurable ||
    definition.action.type === "website_action"
  ) {
    return null;
  }
  const now = new Date().toISOString();
  return {
    schemaVersion: 1,
    id: definition.id,
    gesture,
    name: definition.name,
    description: definition.description,
    source: "preset",
    plan: commandPlan(
      gesture,
      definition.name,
      definition.action,
    ),
    createdAt: now,
    updatedAt: now,
    enabled: true,
  };
}

async function waitForTabComplete(
  tabId: number,
  timeoutMs: number,
  signal: AbortSignal,
) {
  const current = await chrome.tabs.get(tabId);
  if (current.status === "complete") return;
  await new Promise<void>((resolve, reject) => {
    const cleanup = () => {
      clearTimeout(timer);
      chrome.tabs.onUpdated.removeListener(listener);
      signal.removeEventListener("abort", onAbort);
    };
    const listener = (
      updatedTabId: number,
      changeInfo: { status?: string },
    ) => {
      if (updatedTabId !== tabId || changeInfo.status !== "complete") return;
      cleanup();
      resolve();
    };
    const onAbort = () => {
      cleanup();
      reject(new DOMException("Command cancelled.", "AbortError"));
    };
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error("The website did not finish loading in time."));
    }, timeoutMs);
    chrome.tabs.onUpdated.addListener(listener);
    signal.addEventListener("abort", onAbort, { once: true });
  });
}

async function runWebsiteDefault(
  action: WebsiteAction,
  signal: AbortSignal,
) {
  const { parameters } = action;
  const tabs = await chrome.tabs.query({ url: parameters.matchUrlPattern });
  let tab = tabs.find((candidate) => candidate.id !== undefined) ?? null;
  const created = !tab;
  if (!tab) {
    tab = await chrome.tabs.create({
      url: parameters.fallbackUrl,
      active: true,
    });
  } else if (tab.id !== undefined) {
    tab = (await chrome.tabs.update(tab.id, { active: true })) ?? null;
    if (tab?.windowId !== undefined) {
      await chrome.windows.update(tab.windowId, { focused: true });
    }
  }
  if (!tab?.id) throw new Error("Chrome could not activate the website tab.");

  if (
    parameters.automation === "spotify_next_track" &&
    created
  ) {
    return "Spotify opened. Start playback, then repeat Thumbs Down.";
  }

  await waitForTabComplete(tab.id, parameters.timeoutMs, signal);
  const browserAction: BrowserCommandAction =
    parameters.automation === "bolt_prompt"
      ? {
          type: "bolt_prompt",
          parameters: { prompt: parameters.prompt },
        }
      : { type: "spotify_next_track", parameters: {} };
  let receipt;
  try {
    receipt = await sendContentAction(
      tab.id,
      browserAction,
      `website_${crypto.randomUUID()}`,
    );
  } catch {
    await chrome.scripting.executeScript({
      target: { tabId: tab.id, allFrames: true },
      files: ["content/content-script.js"],
    });
    receipt = await sendContentAction(
      tab.id,
      browserAction,
      `website_${crypto.randomUUID()}`,
    );
  }
  if (!receipt.ok) throw new Error(receipt.message);
  return receipt.message;
}

async function executeGesture(gesture: GestureId) {
  await ensureInitialized();
  if (activeCommand) {
    await patchRuntime({
      status: "A Signal command is already running.",
    });
    return;
  }
  const definition = getActiveCommandDefinition(gesture);
  if (definition?.action.type === "website_action") {
    const controller = new AbortController();
    activeCommand = controller;
    await patchRuntime({ status: `Running ${definition.name}…` });
    try {
      const message = await runWebsiteDefault(
        definition.action,
        controller.signal,
      );
      await patchRuntime({ status: message });
    } catch (error) {
      await patchRuntime({
        status:
          error instanceof Error
            ? `${definition.name} stopped: ${error.message}`
            : `${definition.name} stopped.`,
      });
    } finally {
      if (activeCommand === controller) activeCommand = null;
    }
    return;
  }
  const command =
    gesture === "fist"
      ? storedState?.commands.find(
          (candidate) => candidate.gesture === "fist" && candidate.enabled,
        ) ?? null
      : presetCommand(gesture);

  if (!command) {
    await patchRuntime({
      status:
        gesture === "fist"
          ? "Open the side panel and assign a browser-safe Fist command first."
          : "This command is unavailable.",
    });
    return;
  }

  await patchRuntime({ status: `Running ${command.name}…` });
  const controller = new AbortController();
  activeCommand = controller;
  try {
    const receipt = await commandExecutor.execute(command, {
      confirmationsApproved: command.source === "preset",
      signal: controller.signal,
    });
    await patchRuntime({
      status: `${command.name} completed ${receipt.completedSteps} step${receipt.completedSteps === 1 ? "" : "s"}.`,
    });
  } catch (error) {
    await patchRuntime({
      status:
        error instanceof Error
          ? `Command stopped: ${error.message}`
          : "The command stopped.",
    });
  } finally {
    if (activeCommand === controller) activeCommand = null;
  }
}

async function handleTrackingFrame(frame: TrackingFrameMessage) {
  if (!runtimeState.running || runtimeState.paused) return;
  const result = await router.routeTrackingFrame(frame);
  const supported = result.status === "sent";
  const gesture = ACTIVE_COMMAND_GESTURES.includes(
    frame.gesture as ActiveCommandGesture,
  )
    ? (frame.gesture as ActiveCommandGesture)
    : null;
  const update = gestureEngine.update(
    {
      gesture,
      confidence: frame.confidence,
      timestamp: frame.timestamp,
    },
    {
      mode: activeMode(),
      editing: editorOpen,
      supportedTab: supported,
    },
  );

  if (update) {
    try {
      await chrome.runtime.sendMessage(update);
    } catch {
      // No side panel is open.
    }
    if (update.firedNow) void executeGesture(update.gesture);
  }

  const now = Date.now();
  if (now - lastTelemetryAt >= 200 || frame.gesture === "unknown") {
    lastTelemetryAt = now;
    runtimeState.fps = frame.fps ?? runtimeState.fps;
    runtimeState.gesture = frame.gesture === "unknown" ? null : frame.gesture;
    runtimeState.confidence = frame.confidence;
    runtimeState.activeTabSupported = supported;
    runtimeState.commandProgress = update?.progress;
    runtimeState.status =
      result.status === "unsupported"
        ? PROTECTED_PAGE_MESSAGE
        : runtimeState.mode === "commands" && update
          ? `${update.gesture.replace("_", " ")} ${update.phase} at ${Math.round(update.progress * 100)}%.`
          : "Signal is tracking locally.";
    try {
      await chrome.runtime.sendMessage({
        version: 1,
        type: "signal:tracking-state",
        fps: runtimeState.fps,
        gesture: runtimeState.gesture,
        confidence: runtimeState.confidence,
        progress: runtimeState.commandProgress,
        status: runtimeState.status,
      });
    } catch {
      // No side panel is open.
    }
  }
}

async function handleOffscreenMessage(message: unknown) {
  if (!message || typeof message !== "object") return;
  const event = message as {
    version?: number;
    type?: string;
    state?: OffscreenStateMessage["state"];
    fps?: number;
    cameraActive?: boolean;
    error?: string;
    reason?: string;
  };
  if (event.version !== 1) return;

  if (isTrackingFrameMessage(event)) {
    await handleTrackingFrame(event);
    return;
  }

  if (event.type === "signal:offscreen/permission-required") {
    await patchRuntime(
      {
        running: false,
        paused: false,
        camera: "permission",
        status:
          "Camera permission is required. Complete the one-time Signal setup.",
      },
      true,
    );
    await openPermissionSetup();
    return;
  }

  if (event.type === "signal:offscreen/state") {
    const camera: CameraState =
      event.state === "running"
        ? "running"
        : event.state === "paused"
          ? "paused"
          : event.state === "error"
            ? "error"
            : event.state === "requesting-permission" ||
                event.state === "starting"
              ? "starting"
              : "off";
    const stoppedUnexpectedly =
      !stopping &&
      runtimeState.running &&
      runtimeState.camera !== "starting" &&
      (event.state === "idle" || event.state === "stopped");
    await patchRuntime(
      {
        ...(stoppedUnexpectedly
          ? {
              running: false,
              paused: false,
            }
          : {}),
        camera,
        fps: event.fps ?? 0,
        status:
          event.error ??
          (stoppedUnexpectedly
            ? "Signal’s camera stopped unexpectedly. Choose Start Signal to recover."
            : camera === "running"
              ? "Signal is tracking locally across ordinary tabs."
              : camera === "paused"
                ? "Signal is paused. The camera track is off."
                : runtimeState.status),
      },
      stoppedUnexpectedly,
    );
  }
}

async function startSignal() {
  await ensureInitialized();
  runtimeState.mode = "control";
  if (storedState) {
    storedState.settings.mode = "control";
    await storage.save(storedState);
  }
  await refreshActiveTab();
  await patchRuntime(
    {
      running: true,
      paused: false,
      camera: "starting",
      status: "Starting private hand tracking…",
    },
    true,
  );
  try {
    await sendOffscreen("signal:offscreen/start");
    await sendModeToActiveTab();
    return { ok: true };
  } catch (error) {
    await patchRuntime({
      running: false,
      camera: "error",
      status:
        error instanceof Error ? error.message : "Signal could not start.",
    }, true);
    return {
      ok: false,
      error: runtimeState.status,
      permission: runtimeState.camera === "permission",
    };
  }
}

async function stopSignal() {
  stopping = true;
  cancelActiveCommand();
  await stopDemoCapture();
  try {
    try {
      if (offscreenPort || offscreenCreation || (await hasOffscreenDocument())) {
        if (offscreenCreation) await offscreenCreation.catch(() => undefined);
        if (await hasOffscreenDocument()) {
          await sendOffscreen("signal:offscreen/stop");
        }
      }
    } catch {
      // Continue teardown even when the offscreen document disappeared.
    }
    await router.reset("stop");
    resetGestureEngine();
    await closeOffscreenDocument();
    await patchRuntime(
      {
        running: false,
        paused: false,
        camera: "off",
        fps: 0,
        gesture: null,
        confidence: 0,
        commandProgress: undefined,
        status: "Signal stopped. The camera track is off.",
      },
      true,
    );
  } finally {
    stopping = false;
  }
}

async function pauseSignal() {
  cancelActiveCommand();
  await stopDemoCapture();
  await sendOffscreen("signal:offscreen/pause");
  await router.reset("pause");
  resetGestureEngine();
  await patchRuntime(
    {
      paused: true,
      camera: "paused",
      gesture: null,
      confidence: 0,
      commandProgress: undefined,
      status: "Signal is paused. The camera track is off.",
    },
    true,
  );
  await sendModeToActiveTab();
}

async function resumeSignal() {
  await patchRuntime(
    {
      running: true,
      paused: false,
      camera: "starting",
      status: "Resuming private hand tracking…",
    },
    true,
  );
  try {
    await sendOffscreen("signal:offscreen/start");
    await sendModeToActiveTab();
  } catch (error) {
    await patchRuntime(
      {
        running: false,
        paused: false,
        camera: "error",
        status:
          error instanceof Error
            ? error.message
            : "Signal could not resume.",
      },
      true,
    );
    throw error;
  }
}

async function planInstruction(instruction: string) {
  const response = await fetch(`${PUBLIC_SITE}/api/v1/plan`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      schemaVersion: 1,
      requestId: `extension_${Date.now().toString(36)}`,
      request: instruction,
      targetGesture: "fist",
      actionCatalog: [
        "open_url",
        "wait",
        "show_notification",
        "speak_text",
        "discord_webhook",
        "media_control",
        "show_overlay",
      ],
    }),
  });
  const body = (await response.json()) as {
    status?: string;
    plan?: CommandPlan;
    question?: string;
    warnings?: string[];
    usedDeterministicFallback?: boolean;
  };
  if (!response.ok) throw new Error("Signal’s planner is unavailable.");
  if (body.status === "needs_clarification") {
    throw new Error(body.question ?? "The planner needs one more detail.");
  }
  if (body.status !== "planned" || !body.plan) {
    throw new Error("The planner returned an invalid response.");
  }
  return {
    plan: body.plan,
    name: body.plan.name,
    fallback: body.usedDeterministicFallback === true,
  };
}

type CapturedDemoAction = {
  type?: unknown;
  selector?: unknown;
};

function planFromDemonstration(actions: unknown, origin: unknown): CommandPlan {
  if (!Array.isArray(actions)) {
    throw new Error("Signal did not receive a valid demonstration.");
  }
  if (
    typeof origin !== "string" ||
    !/^https?:\/\/[^/]+$/i.test(origin)
  ) {
    throw new Error("Signal did not receive a safe demonstration origin.");
  }
  const steps: CommandPlan["steps"] = [];
  const seenFocus = new Set<string>();
  for (const candidate of actions.slice(0, 64)) {
    if (!candidate || typeof candidate !== "object") continue;
    const action = candidate as CapturedDemoAction;
    if (typeof action.selector !== "string" || action.selector.length > 512) {
      continue;
    }
    let browserAction: BrowserCommandAction | null = null;
    if (action.type === "click") {
      browserAction = {
        type: "click_selector",
        parameters: { selector: action.selector, origin },
      };
    } else if (
      (action.type === "focus" || action.type === "input") &&
      !seenFocus.has(action.selector)
    ) {
      seenFocus.add(action.selector);
      browserAction = {
        type: "focus_field",
        parameters: { selector: action.selector, origin },
      };
    } else if (action.type === "scroll" && action.selector !== "document") {
      browserAction = {
        type: "scroll_to_selector",
        parameters: {
          selector: action.selector,
          origin,
          behavior: "smooth",
          block: "center",
        },
      };
    }
    if (!browserAction) continue;
    steps.push({
      id: `step-${steps.length + 1}`,
      action: browserAction,
      timeoutMs: 8_000,
      onFailure: "stop",
      confirmation: { mode: "none", reason: "" },
    });
  }
  if (steps.length === 0) {
    throw new Error(
      "No safe click, focus, or element-scroll action was captured.",
    );
  }
  return {
    schemaVersion: 1,
    id: `demo-${Date.now().toString(36)}`,
    name: "Taught browser workflow",
    description:
      "Reviewed semantic browser actions captured without video or field values.",
    steps,
    timeoutMs: Math.min(
      300_000,
      steps.reduce((sum, step) => sum + step.timeoutMs, 0) + 3_000,
    ),
    onFailure: "stop",
    confirmation: { mode: "first_run", reason: "Review taught page selectors." },
    createdSource: "demo_recording",
    secretReferences: [],
  };
}

async function stopDemoCapture() {
  const tabId = demoTabId;
  const sessionId = demoSessionId;
  demoTabId = null;
  demoSessionId = null;
  if (tabId === null || sessionId === null) return null;
  try {
    return await chrome.tabs.sendMessage(tabId, {
      version: 1,
      type: "signal:demo/stop",
      sessionId,
    });
  } catch {
    return null;
  }
}

async function profileForExport(): Promise<StoredProfile> {
  await ensureInitialized();
  return {
    schemaVersion: 1,
    id: "signal.local.default",
    name: "Signal local profile",
    description: "Exported from the Signal Chrome extension.",
    commands: storedState?.commands ?? [],
    settings: storedState?.settings,
    tuning: storedState?.tuning,
  };
}

async function handleSidePanelMessage(
  message: Record<string, unknown>,
  sender: chrome.runtime.MessageSender,
) {
  await ensureInitialized();
  switch (message.type) {
    case "signal:sidepanel/status":
      return {
        ok: true,
        state: { ...runtimeState },
        fistCommand:
          storedState?.commands.find((command) => command.gesture === "fist") ??
          null,
        tuning: {
          sensitivity:
            storedState?.tuning.pointerSensitivity ??
            DEFAULT_TUNING.pointerSensitivity,
          smoothing:
            storedState?.tuning.pointerSmoothing ??
            DEFAULT_TUNING.pointerSmoothing,
        },
      };
    case "signal:sidepanel/start":
      return enqueueLifecycle(startSignal);
    case "signal:sidepanel/stop":
      await enqueueLifecycle(stopSignal);
      return { ok: true };
    case "signal:sidepanel/pause":
      await enqueueLifecycle(pauseSignal);
      return { ok: true };
    case "signal:sidepanel/resume":
      await enqueueLifecycle(resumeSignal);
      return { ok: true };
    case "signal:sidepanel/mode": {
      const mode =
        message.mode === "commands" ? "commands" : "control";
      runtimeState.mode = mode;
      if (mode === "control") cancelActiveCommand();
      if (storedState) {
        storedState.settings.mode = mode;
        await storage.save(storedState);
      }
      resetGestureEngine();
      await sendModeToActiveTab();
      await patchRuntime({
        status: `${mode === "control" ? "Control" : "Commands"} mode selected.`,
      });
      return { ok: true };
    }
    case "signal:sidepanel/editor":
      editorOpen = message.open === true;
      if (editorOpen) {
        cancelActiveCommand();
        resetGestureEngine();
      } else {
        await stopDemoCapture();
      }
      return { ok: true };
    case "signal:sidepanel/open-permission":
      await openPermissionSetup();
      return { ok: true };
    case "signal:sidepanel/plan": {
      if (typeof message.instruction !== "string" || !message.instruction.trim()) {
        return { ok: false, error: "Describe the command first." };
      }
      try {
        return { ok: true, ...(await planInstruction(message.instruction.trim())) };
      } catch (error) {
        return {
          ok: false,
          error:
            error instanceof Error ? error.message : "Plan generation failed.",
        };
      }
    }
    case "signal:sidepanel/save-command": {
      const parsed = safeParseSignalCommand(message.command);
      if (!parsed.success || parsed.data.gesture !== "fist") {
        return {
          ok: false,
          error: parsed.success
            ? "Only the Fist command is editable here."
            : parsed.error.message,
        };
      }
      await storage.saveCommand(parsed.data);
      storedState = await storage.load();
      return { ok: true };
    }
    case "signal:sidepanel/demo-start":
    case "signal:sidepanel/demo-stop": {
      try {
        if (message.type === "signal:sidepanel/demo-start") {
          await stopDemoCapture();
          const tab = await getActiveTab();
          if (tab?.id === undefined || !isSupportedPageUrl(tab.url)) {
            return { ok: false, error: PROTECTED_PAGE_MESSAGE };
          }
          demoSessionId = crypto.randomUUID();
          demoTabId = tab.id;
          const response = await chrome.tabs.sendMessage(tab.id, {
            version: 1,
            type: "signal:demo/start",
            sessionId: demoSessionId,
            maxActions: 64,
          });
          return { ok: true, demonstration: response };
        }
        const response = await stopDemoCapture();
        if (!response) {
          return {
            ok: false,
            error: "Signal did not have an active demonstration to stop.",
          };
        }
        const result = response as {
          actions?: unknown;
          origin?: unknown;
          truncated?: boolean;
        };
        const plan = planFromDemonstration(result?.actions, result?.origin);
        return {
          ok: true,
          demonstration: response,
          plan,
          name: plan.name,
          truncated: result?.truncated === true,
        };
      } catch {
        demoTabId = null;
        demoSessionId = null;
        return {
          ok: false,
          error: "Signal could not capture actions on this page.",
        };
      }
    }
    case "signal:sidepanel/export":
      return { ok: true, profile: await profileForExport() };
    case "signal:sidepanel/import":
      try {
        const profile = await storage.importProfile(message.profile);
        if (storedState) {
          for (const command of profile.commands) {
            await storage.saveCommand(command);
          }
        }
        storedState = await storage.load();
        return { ok: true };
      } catch (error) {
        return {
          ok: false,
          error:
            error instanceof Error ? error.message : "The profile is invalid.",
        };
      }
    case "signal:sidepanel/tuning": {
      if (!storedState || !message.tuning || typeof message.tuning !== "object") {
        return { ok: false, error: "Tuning values are invalid." };
      }
      const tuning = message.tuning as {
        sensitivity?: unknown;
        smoothing?: unknown;
      };
      storedState.tuning = sanitizeTuning({
        ...storedState.tuning,
        pointerSensitivity:
          typeof tuning.sensitivity === "number"
            ? tuning.sensitivity
            : storedState.tuning.pointerSensitivity,
        pointerSmoothing:
          typeof tuning.smoothing === "number"
            ? tuning.smoothing
            : storedState.tuning.pointerSmoothing,
      });
      await storage.save(storedState);
      await sendTuningToActiveTab();
      return { ok: true };
    }
    case "signal:setup/permission-granted":
      if (sender.tab?.id !== undefined) {
        void chrome.tabs.remove(sender.tab.id).catch(() => undefined);
      }
      return enqueueLifecycle(startSignal);
    default:
      return undefined;
  }
}

async function handleRuntimeMessage(
  message: unknown,
  sender: chrome.runtime.MessageSender,
) {
  if (!message || typeof message !== "object") return undefined;
  const event = message as Record<string, unknown> & {
    version?: number;
    type?: string;
  };
  if (event.version !== 1 || typeof event.type !== "string") return undefined;

  if (
    event.type.startsWith("signal:sidepanel/") ||
    event.type === "signal:setup/permission-granted"
  ) {
    return handleSidePanelMessage(event, sender);
  }

  if (event.type === "signal:zoom-request") {
    const tabId = sender.tab?.id;
    if (
      tabId === undefined ||
      tabId !== router.activeTabId ||
      typeof event.delta !== "number"
    ) {
      return { ok: false, error: "Stale zoom request." };
    }
    const current = await chrome.tabs.getZoom(tabId);
    const status = await zoom.set(
      tabId,
      current + event.delta,
      typeof event.timestamp === "number" ? event.timestamp : Date.now(),
    );
    await chrome.tabs.sendMessage(tabId, status);
    return status;
  }

  if (event.type === "signal:content-ready") {
    const tab = sender.tab ? routable(sender.tab) : null;
    const activeTab = await getActiveTab();
    if (
      event.topFrame === true &&
      tab?.id !== undefined &&
      activeTab?.id === tab.id
    ) {
      const result =
        event.supported === true
          ? await router.activate(tab)
          : { status: "unsupported" as const };
      const supported = result.status === "sent";
      await patchRuntime({
        activeTabSupported: supported,
        status: supported ? runtimeState.status : PROTECTED_PAGE_MESSAGE,
      });
      if (supported) {
        await sendModeToActiveTab();
        await sendTuningToActiveTab();
      }
    }
    return { ok: true, mode: activeMode() };
  }

  if (
    event.type === "signal:interaction-reset" ||
    event.type === "signal:content-action-result"
  ) {
    return { ok: true };
  }

  return undefined;
}

async function ensureInitialized() {
  if (initialization) return initialization;
  initialization = (async () => {
    storedState = await storage.load();
    const storedMode = storedState.settings.mode;
    runtimeState.mode = storedMode === "commands" ? "commands" : "control";
    gestureEngine = new CommandGestureEngine({
      holdMs: storedState.tuning.holdMs,
      cooldownMs: storedState.tuning.cooldownMs,
      minimumConfidence: storedState.tuning.minimumConfidence,
    });
    const session = await chrome.storage.session.get(SESSION_KEY);
    const previous = session[SESSION_KEY] as StoredRuntimeSession | undefined;
    runtimeState.running = previous?.running === true;
    runtimeState.paused = previous?.paused === true;
    if (runtimeState.running && runtimeState.paused) {
      runtimeState.camera = "paused";
      runtimeState.status = "Signal is paused. The camera track is off.";
    }
    await refreshActiveTab("service-worker-restart");
    if (runtimeState.running && !runtimeState.paused) {
      try {
        await sendOffscreen("signal:offscreen/ping");
        await sendOffscreen("signal:offscreen/start");
      } catch {
        runtimeState.running = false;
        runtimeState.camera = "error";
        runtimeState.status =
          "Signal’s camera runtime stopped. Choose Start Signal to recover.";
      }
    }
    await broadcastRuntime();
  })().catch((error) => {
    initialization = null;
    throw error;
  });
  return initialization;
}

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== OFFSCREEN_PORT_NAME) return;
  offscreenPort = port;
  port.onMessage.addListener((message) => {
    void handleOffscreenMessage(message);
  });
  port.onDisconnect.addListener(() => {
    if (offscreenPort === port) offscreenPort = null;
  });
  port.postMessage({ version: 1, type: "signal:offscreen/ping" });
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  void handleRuntimeMessage(message, sender)
    .then((response) => sendResponse(response))
    .catch((error) =>
      sendResponse({
        ok: false,
        error: error instanceof Error ? error.message : "Signal request failed.",
      }),
    );
  return true;
});

chrome.tabs.onActivated.addListener(({ tabId }) => {
  void getActiveTab().then(async (tab) => {
    if (tab?.id !== tabId) return;
    const candidate = routable(tab);
    if (!candidate) return;
    zoom.clear();
    resetGestureEngine();
    const result = await router.activate(candidate, "tab-change");
    const supported = result.status === "sent";
    await patchRuntime({
      activeTabSupported: supported,
      status: supported
        ? "Signal moved to the active tab."
        : PROTECTED_PAGE_MESSAGE,
    });
    if (supported) {
      await sendModeToActiveTab();
      await sendTuningToActiveTab();
    }
  });
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (
    tabId !== router.activeTabId ||
    (!changeInfo.url && changeInfo.status !== "complete")
  ) {
    return;
  }
  void router.navigationCommitted(tabId, changeInfo.url ?? tab.url).then(
    async (result) => {
      resetGestureEngine();
      zoom.clear(tabId);
      const supported = result.status === "sent";
      await patchRuntime({
        activeTabSupported: supported,
        status: supported ? "Signal reset for the new page." : PROTECTED_PAGE_MESSAGE,
      });
      if (supported) {
        await sendModeToActiveTab();
        await sendTuningToActiveTab();
      }
    },
  );
});

chrome.tabs.onRemoved.addListener((tabId) => {
  zoom.clear(tabId);
  if (demoTabId === tabId) {
    demoTabId = null;
    demoSessionId = null;
  }
  if (router.activeTabId === tabId) {
    resetGestureEngine();
    void refreshActiveTab();
  }
});

chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId !== chrome.windows.WINDOW_ID_NONE) void refreshActiveTab();
});

chrome.runtime.onInstalled.addListener(() => {
  void chrome.sidePanel
    .setPanelBehavior({ openPanelOnActionClick: true })
    .catch(() => undefined);
  void ensureInitialized().catch(() => undefined);
});

chrome.runtime.onStartup.addListener(() => {
  void ensureInitialized().catch(() => undefined);
});

void chrome.sidePanel
  .setPanelBehavior({ openPanelOnActionClick: true })
  .catch(() => undefined);
void ensureInitialized().catch(() => undefined);
