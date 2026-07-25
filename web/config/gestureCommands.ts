export const gestureIds = [
  "one",
  "two",
  "three",
  "four",
  "five",
  "thumbs_up",
  "thumbs_down",
  "c_shape",
  "fist",
] as const;

export type GestureId = (typeof gestureIds)[number];

export type PresetGestureCommand = {
  gesture: GestureId;
  label: string;
  mark: string;
  commandName: string;
  description: string;
  actionType: string;
  availability: "ready" | "native_required" | "unavailable";
  custom: boolean;
};

export const gestureCommands: readonly PresetGestureCommand[] = [
  {
    gesture: "one",
    label: "One",
    mark: "1",
    commandName: "Open Spotify",
    description: "Bring Spotify to the foreground.",
    actionType: "Open app",
    availability: "native_required",
    custom: false,
  },
  {
    gesture: "two",
    label: "Two",
    mark: "2",
    commandName: "Open Gmail",
    description: "Open Gmail in the default browser.",
    actionType: "Open URL",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "three",
    label: "Three",
    mark: "3",
    commandName: "Open GitHub",
    description: "Open the project workspace on GitHub.",
    actionType: "Open URL",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "four",
    label: "Four",
    mark: "4",
    commandName: "Open Calendar",
    description: "Bring Calendar to the foreground.",
    actionType: "Open app",
    availability: "native_required",
    custom: false,
  },
  {
    gesture: "five",
    label: "Five",
    mark: "5",
    commandName: "Start Focus Mode",
    description: "Run the reviewed focus workflow.",
    actionType: "Multi-step",
    availability: "native_required",
    custom: false,
  },
  {
    gesture: "thumbs_up",
    label: "Thumbs Up",
    mark: "↑",
    commandName: "Send “Demo complete”",
    description: "Use a configured Discord connection.",
    actionType: "Cloud action",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "thumbs_down",
    label: "Thumbs Down",
    mark: "↓",
    commandName: "Pause Media",
    description: "Pause the active media session.",
    actionType: "Media control",
    availability: "native_required",
    custom: false,
  },
  {
    gesture: "c_shape",
    label: "C",
    mark: "C",
    commandName: "Ask Claude",
    description: "Open a reviewed AI workflow.",
    actionType: "Shortcut",
    availability: "native_required",
    custom: false,
  },
  {
    gesture: "fist",
    label: "Fist",
    mark: "●",
    commandName: "Custom command",
    description: "Describe it or teach it by recording.",
    actionType: "Programmable",
    availability: "ready",
    custom: true,
  },
] as const;

export const presetGestures = gestureCommands.filter(
  (command) => !command.custom,
);

export const fistGesture = gestureCommands.find(
  (command) => command.gesture === "fist",
)!;
