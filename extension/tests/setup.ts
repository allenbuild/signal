import { vi } from "vitest";

const listeners: Array<(message: unknown) => void> = [];

Object.defineProperty(globalThis, "chrome", {
  configurable: true,
  value: {
    runtime: {
      getURL: (path: string) => `chrome-extension://signal/${path}`,
      sendMessage: vi.fn(async () => ({ ok: true })),
      connect: vi.fn(() => ({
        name: "signal:test",
        postMessage: vi.fn(),
        disconnect: vi.fn(),
        onMessage: { addListener: vi.fn() },
        onDisconnect: { addListener: vi.fn() },
      })),
      onMessage: {
        addListener: vi.fn((listener: (message: unknown) => void) => {
          listeners.push(listener);
        }),
        removeListener: vi.fn(),
      },
    },
    storage: {
      local: {
        get: vi.fn(async () => ({})),
        set: vi.fn(async () => undefined),
        remove: vi.fn(async () => undefined),
      },
      sync: {
        get: vi.fn(async () => ({})),
        set: vi.fn(async () => undefined),
      },
    },
    tabs: {
      query: vi.fn(async () => []),
      sendMessage: vi.fn(async () => undefined),
      getZoom: vi.fn(async () => 1),
      setZoom: vi.fn(async () => undefined),
    },
  },
});

export { listeners };
