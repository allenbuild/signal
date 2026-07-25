import { isSafeBrowserUrl } from "./schema";

export interface ActionTabLocation {
  href?: string;
  replace?(url: string): void;
}

export interface ActionTabWindow {
  readonly closed: boolean;
  location: ActionTabLocation;
  focus?(): void;
}

export type ActionTabOpen = (
  url: string,
  target: string,
  features?: string,
) => ActionTabWindow | null;

export type ActionTabNavigationResult =
  | { status: "navigated"; url: string }
  | {
      status: "requires_same_tab_confirmation";
      url: string;
      reason: "not_prepared" | "closed" | "navigation_failed";
    }
  | { status: "rejected"; reason: "unsafe_url" };

/**
 * The caller must invoke prepare from a real user activation (Start Signal or
 * Enable Action Tab). Gesture execution only reuses this handle.
 */
export class PreparedActionTab {
  private handle: ActionTabWindow | null = null;

  get available(): boolean {
    return Boolean(this.handle && !this.handle.closed);
  }

  prepare(openWindow: ActionTabOpen): "prepared" | "blocked" {
    try {
      const handle = openWindow(
        "about:blank",
        "signal-action-tab",
        "noopener=false",
      );
      if (!handle || handle.closed) {
        this.handle = null;
        return "blocked";
      }
      this.handle = handle;
      return "prepared";
    } catch {
      this.handle = null;
      return "blocked";
    }
  }

  navigate(url: string): ActionTabNavigationResult {
    if (!isSafeBrowserUrl(url)) {
      return { status: "rejected", reason: "unsafe_url" };
    }
    const handle = this.handle;
    if (!handle) {
      return {
        status: "requires_same_tab_confirmation",
        url,
        reason: "not_prepared",
      };
    }
    if (handle.closed) {
      this.handle = null;
      return {
        status: "requires_same_tab_confirmation",
        url,
        reason: "closed",
      };
    }
    try {
      if (handle.location.replace) handle.location.replace(url);
      else handle.location.href = url;
      handle.focus?.();
      return { status: "navigated", url };
    } catch {
      this.handle = null;
      return {
        status: "requires_same_tab_confirmation",
        url,
        reason: "navigation_failed",
      };
    }
  }

  navigateSameTab(
    url: string,
    confirmed: boolean,
    saveState: () => void,
    navigate: (url: string) => void,
  ): ActionTabNavigationResult {
    if (!isSafeBrowserUrl(url)) {
      return { status: "rejected", reason: "unsafe_url" };
    }
    if (!confirmed) {
      return {
        status: "requires_same_tab_confirmation",
        url,
        reason: "not_prepared",
      };
    }
    saveState();
    navigate(url);
    return { status: "navigated", url };
  }

  forget(): void {
    this.handle = null;
  }
}
