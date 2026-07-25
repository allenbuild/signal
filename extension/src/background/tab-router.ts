import {
  PROTECTED_PAGE_MESSAGE,
  resetMessage,
  type SignalMessage,
  type TrackingFrameMessage,
} from "../shared/messages";

export type RoutableTab = {
  id: number;
  url?: string;
  active?: boolean;
  windowId?: number;
  index?: number;
};

export type TabRouterDependencies = {
  getActiveTab(): Promise<RoutableTab | null>;
  sendMessage(tabId: number, message: SignalMessage): Promise<unknown>;
  injectContentScript?(tabId: number): Promise<void>;
  canAccessTab?(tab: RoutableTab): Promise<boolean>;
  onUnsupported?(message: string, tab?: RoutableTab): void;
  activeValidationIntervalMs?: number;
};

export type RouteResult =
  | { status: "sent"; tabId: number }
  | { status: "stale" | "no-active-tab" | "unsupported" | "unavailable" };

const WEB_STORE_HOSTS = new Set([
  "chrome.google.com",
  "chromewebstore.google.com",
]);

export function isSupportedPageUrl(value: string | undefined) {
  if (!value) return false;
  try {
    const url = new URL(value);
    if (!["http:", "https:"].includes(url.protocol)) return false;
    if (
      WEB_STORE_HOSTS.has(url.hostname.toLowerCase()) &&
      (url.hostname.toLowerCase() !== "chrome.google.com" ||
        url.pathname.startsWith("/webstore"))
    ) {
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

export class ActiveTabRouter {
  private activeTab: RoutableTab | null = null;
  private generation = 0;
  private lastSequence = -1;
  private lastSessionId: string | null = null;
  private lastActiveValidationAt = Number.NEGATIVE_INFINITY;
  private routing: Promise<void> = Promise.resolve();

  constructor(private readonly dependencies: TabRouterDependencies) {}

  get activeTabId() {
    return this.activeTab?.id ?? null;
  }

  get currentGeneration() {
    return this.generation;
  }

  async restore(): Promise<RouteResult> {
    const tab = await this.dependencies.getActiveTab();
    if (!tab) return { status: "no-active-tab" };
    return this.activate(tab, "service-worker-restart");
  }

  async activate(
    tab: RoutableTab,
    reason: "tab-change" | "service-worker-restart" = "tab-change",
  ): Promise<RouteResult> {
    const previous = this.activeTab;
    const changed = previous?.id !== tab.id;
    if (changed && previous && isSupportedPageUrl(previous.url)) {
      await this.sendBestEffort(
        previous.id,
        resetMessage("tab-change", this.generation + 1),
        false,
      );
    }

    this.activeTab = tab;
    this.generation += 1;
    this.lastSequence = -1;
    this.lastSessionId = null;
    const generation = this.generation;

    if (!(await this.supports(tab))) {
      this.dependencies.onUnsupported?.(PROTECTED_PAGE_MESSAGE, tab);
      return { status: "unsupported" };
    }

    const sent = await this.sendBestEffort(
      tab.id,
      resetMessage(reason, generation),
      true,
    );
    if (generation !== this.generation || this.activeTab?.id !== tab.id) {
      return { status: "stale" };
    }
    return sent ? { status: "sent", tabId: tab.id } : { status: "unavailable" };
  }

  async navigationCommitted(
    tabId: number,
    url?: string,
  ): Promise<RouteResult> {
    if (this.activeTab?.id !== tabId) return { status: "stale" };
    this.activeTab = { ...this.activeTab, url: url ?? this.activeTab.url };
    this.generation += 1;
    this.lastSequence = -1;
    this.lastSessionId = null;
    const generation = this.generation;

    if (!(await this.supports(this.activeTab))) {
      this.dependencies.onUnsupported?.(
        PROTECTED_PAGE_MESSAGE,
        this.activeTab,
      );
      return { status: "unsupported" };
    }

    const sent = await this.sendBestEffort(
      tabId,
      resetMessage("navigation", generation),
      true,
    );
    return sent ? { status: "sent", tabId } : { status: "unavailable" };
  }

  async reset(
    reason: "tracking-loss" | "pause" | "stop",
  ): Promise<RouteResult> {
    const tab = this.activeTab;
    if (!tab) return { status: "no-active-tab" };
    this.generation += 1;
    this.lastSequence = -1;
    this.lastSessionId = null;
    if (!(await this.supports(tab))) return { status: "unsupported" };
    const sent = await this.sendBestEffort(
      tab.id,
      resetMessage(reason, this.generation),
      true,
    );
    return sent ? { status: "sent", tabId: tab.id } : { status: "unavailable" };
  }

  async routeTrackingFrame(
    frame: TrackingFrameMessage,
  ): Promise<RouteResult> {
    const operation = this.routing.then(() => this.performRoute(frame));
    this.routing = operation.then(
      () => undefined,
      () => undefined,
    );
    return operation;
  }

  private async synchronizeActiveTab(
    timestamp: number,
  ): Promise<RouteResult | null> {
    const interval = Math.max(
      0,
      this.dependencies.activeValidationIntervalMs ?? 250,
    );
    if (
      this.activeTab &&
      timestamp - this.lastActiveValidationAt < interval
    ) {
      return null;
    }
    this.lastActiveValidationAt = timestamp;
    const browserActiveTab = await this.dependencies.getActiveTab();
    if (!browserActiveTab) return { status: "no-active-tab" };
    if (
      this.activeTab?.id !== browserActiveTab.id ||
      this.activeTab.url !== browserActiveTab.url
    ) {
      return this.activate(browserActiveTab, "tab-change");
    }
    return null;
  }

  private async performRoute(
    frame: TrackingFrameMessage,
  ): Promise<RouteResult> {
    const synchronization = await this.synchronizeActiveTab(frame.timestamp);
    if (synchronization && synchronization.status !== "sent") {
      return synchronization;
    }
    const tab = this.activeTab;
    const generation = this.generation;
    if (!tab) return { status: "no-active-tab" };
    if (frame.sessionId && frame.sessionId !== this.lastSessionId) {
      this.lastSessionId = frame.sessionId;
      this.lastSequence = -1;
    }
    if (frame.sequence <= this.lastSequence) return { status: "stale" };
    if (!(await this.supports(tab))) {
      this.dependencies.onUnsupported?.(PROTECTED_PAGE_MESSAGE, tab);
      return { status: "unsupported" };
    }

    if (generation !== this.generation || this.activeTab?.id !== tab.id) {
      return { status: "stale" };
    }
    const sent = await this.sendBestEffort(tab.id, frame, true);
    if (generation !== this.generation || this.activeTab?.id !== tab.id) {
      return { status: "stale" };
    }
    if (!sent) return { status: "unavailable" };
    this.lastSequence = frame.sequence;
    return { status: "sent", tabId: tab.id };
  }

  private async supports(tab: RoutableTab) {
    if (!isSupportedPageUrl(tab.url)) return false;
    return (await this.dependencies.canAccessTab?.(tab)) ?? true;
  }

  private async sendBestEffort(
    tabId: number,
    message: SignalMessage,
    allowInjection: boolean,
  ) {
    try {
      await this.dependencies.sendMessage(tabId, message);
      return true;
    } catch {
      if (!allowInjection || !this.dependencies.injectContentScript) return false;
    }

    try {
      await this.dependencies.injectContentScript(tabId);
      await this.dependencies.sendMessage(tabId, message);
      return true;
    } catch {
      return false;
    }
  }
}
