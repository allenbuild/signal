"use client";

import {
  ChangeEvent,
  FormEvent,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  actionPlanSchema,
  plannerResponseSchema,
  profileSchema,
} from "@/lib/contracts";
import {
  checkPublicHttpsLiteralHost,
  containsSecretMaterial,
} from "@/lib/security";

const GESTURES = [
  { id: "one", label: "One", mark: "1" },
  { id: "two", label: "Two", mark: "2" },
  { id: "three", label: "Three", mark: "3" },
  { id: "four", label: "Four", mark: "4" },
  { id: "five", label: "Five", mark: "5" },
  { id: "fist", label: "Fist", mark: "✊" },
  { id: "thumbs_up", label: "Thumbs up", mark: "↑" },
  { id: "thumbs_down", label: "Thumbs down", mark: "↓" },
  { id: "c_shape", label: "C shape", mark: "C" },
] as const;

const ACTION_CATALOG = [
  "open_application",
  "open_url",
  "open_deep_link",
  "keyboard_shortcut",
  "type_text",
  "wait",
  "show_notification",
  "speak_text",
  "play_sound",
  "set_clipboard",
  "read_clipboard_and_transform",
  "run_apple_shortcut",
  "run_applescript_template",
  "http_request",
  "discord_webhook",
  "slack_webhook",
  "media_control",
  "set_volume",
  "show_overlay",
  "focus_application",
  "click_screen_point",
  "scroll_amount",
  "zoom_steps",
  "conditional",
] as const;

const ACTION_CHOICES = [
  {
    type: "open_url",
    label: "Open a URL",
    description: "Open a public HTTPS page.",
    capability: "Browser-safe",
  },
  {
    type: "open_application",
    label: "Open an app",
    description: "Launch an installed Mac app.",
    capability: "Native Mac required",
  },
  {
    type: "speak_text",
    label: "Speak text",
    description: "Read a short local cue aloud.",
    capability: "Native Mac required",
  },
  {
    type: "show_notification",
    label: "Show notification",
    description: "Present a native notification.",
    capability: "Native Mac required",
  },
  {
    type: "wait",
    label: "Wait",
    description: "Pause before the next step.",
    capability: "Browser-safe",
  },
  {
    type: "media_control",
    label: "Media control",
    description: "Play, pause, or change track.",
    capability: "Native Mac required",
  },
  {
    type: "set_volume",
    label: "Set volume",
    description: "Choose the Mac output volume.",
    capability: "Native Mac required",
  },
  {
    type: "discord_webhook",
    label: "Discord message",
    description: "Use a configured secret reference.",
    capability: "Cloud action",
  },
] as const;

type Gesture = (typeof GESTURES)[number]["id"];
type PreferredMode = "touch" | "commands" | "hybrid";
type FailurePolicy = "stop" | "continue" | "ask";
type ConfirmationMode = "none" | "first_run" | "every_run";

type Confirmation = {
  mode: ConfirmationMode;
  reason: string;
};

type SignalAction = {
  type: string;
  parameters: Record<string, unknown>;
};

type PlanStep = {
  id: string;
  action: SignalAction;
  timeoutMs: number;
  onFailure: FailurePolicy;
  confirmation: Confirmation;
};

type SecretReference = {
  id: string;
  provider: "discord" | "slack" | "http_bearer" | "http_basic" | "http_api_key";
  purpose: string;
  storage: "keychain_or_server_environment";
};

type ActionPlan = {
  schemaVersion: 1;
  id: string;
  name: string;
  description: string;
  steps: PlanStep[];
  timeoutMs: number;
  onFailure: FailurePolicy;
  confirmation: Confirmation;
  createdSource: "visual" | "natural_language" | "demo_recording" | "import";
  secretReferences: SecretReference[];
};

type GestureMapping = {
  gesture: Gesture;
  enabled: boolean;
  holdDurationMs: number;
  cooldownMs: number;
  activation: "one_shot" | "repeat";
  repeatIntervalMs?: number;
  allowedBundleIdentifiers: string[];
  preferredMode?: "commands" | "hybrid";
  plan: ActionPlan;
};

type ShareMetadata = {
  visibility: "private" | "unlisted";
  shareCode?: string;
};

type SignalProfile = {
  schemaVersion: 1;
  id: string;
  name: string;
  description: string;
  preferredMode: PreferredMode;
  hybridOneBehavior: "pointer" | "command";
  mappings: GestureMapping[];
  share: ShareMetadata;
};

type ShareResult = {
  schemaVersion: 1;
  shareCode: string;
  profileURL: string;
};

type ManualFields = {
  url: string;
  appName: string;
  bundleIdentifier: string;
  text: string;
  title: string;
  body: string;
  durationMs: string;
  mediaCommand: "toggle_play_pause" | "play" | "pause" | "next" | "previous";
  volume: string;
  discordMessage: string;
  secretRef: string;
};

const STORAGE_KEY = "signal.guest-profile.v1";
const SHARE_CODE_PATTERN = /^SIG1-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/;
const IDENTIFIER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

const defaultManualFields: ManualFields = {
  url: "https://",
  appName: "TextEdit",
  bundleIdentifier: "com.apple.TextEdit",
  text: "Focus mode",
  title: "Signal",
  body: "Your gesture command is complete.",
  durationMs: "1000",
  mediaCommand: "toggle_play_pause",
  volume: "50",
  discordMessage: "Demo complete",
  secretRef: "my-discord-webhook",
};

function newProfile(): SignalProfile {
  return {
    schemaVersion: 1,
    id: `signal.guest.${Date.now()}`,
    name: "My Signal profile",
    description: "A guest profile built in the browser.",
    preferredMode: "hybrid",
    hybridOneBehavior: "pointer",
    mappings: [],
    share: { visibility: "private" },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readPlan(value: unknown): ActionPlan | null {
  const parsed = actionPlanSchema.safeParse(value);
  return parsed.success ? (parsed.data as unknown as ActionPlan) : null;
}

function readProfile(value: unknown): SignalProfile | null {
  const parsed = profileSchema.safeParse(value);
  return parsed.success ? (parsed.data as unknown as SignalProfile) : null;
}

function capabilityFor(actionType: string) {
  if (["http_request", "discord_webhook", "slack_webhook"].includes(actionType)) {
    return "Cloud action";
  }
  if (["open_url", "wait"].includes(actionType)) return "Browser-safe";
  return "Native Mac required";
}

function titleForAction(actionType: string) {
  return actionType
    .split("_")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function summarizeAction(action: SignalAction) {
  const parameters = action.parameters;
  switch (action.type) {
    case "open_url":
      return `Open ${String(parameters.url ?? "a public URL")}`;
    case "open_application":
      return `Open ${String(
        parameters.applicationName ?? parameters.bundleIdentifier ?? "an app",
      )}`;
    case "speak_text":
      return `Say “${String(parameters.text ?? "")}”`;
    case "show_notification":
      return `Show “${String(parameters.title ?? "notification")}”`;
    case "wait":
      return `Wait ${Number(parameters.durationMs ?? 0) / 1000} seconds`;
    case "media_control":
      return `Media: ${String(parameters.command ?? "").replaceAll("_", " ")}`;
    case "set_volume":
      return `Set volume to ${String(parameters.percent ?? 0)}%`;
    case "discord_webhook":
      return `Send “${String(parameters.message ?? "")}” to configured Discord`;
    case "type_text":
      return `Type “${String(parameters.text ?? "")}”`;
    case "keyboard_shortcut":
      return "Send the reviewed keyboard shortcut";
    case "conditional":
      return "Choose a reviewed action branch";
    default:
      return titleForAction(action.type);
  }
}

function actionConfirmation(type: string): Confirmation {
  if (["discord_webhook", "slack_webhook", "http_request"].includes(type)) {
    return {
      mode: "every_run",
      reason: "Sends the displayed content to an external service.",
    };
  }
  if (["wait", "speak_text", "show_notification"].includes(type)) {
    return { mode: "none", reason: "This action has no hidden input." };
  }
  return {
    mode: "first_run",
    reason: "Review this Mac action before its first run.",
  };
}

function calculatePlanTimeout(steps: PlanStep[]) {
  const total = steps.reduce((sum, step) => sum + step.timeoutMs, 0) + 5000;
  return Math.max(100, Math.min(300000, total));
}

export function SignalBuilder() {
  const [profile, setProfile] = useState<SignalProfile>(() => newProfile());
  const [selectedGesture, setSelectedGesture] = useState<Gesture>("thumbs_up");
  const [instruction, setInstruction] = useState(
    "When I give a thumbs up, open my focus playlist, say Focus mode, and send Demo complete to Discord.",
  );
  const [previewPlan, setPreviewPlan] = useState<ActionPlan | null>(null);
  const [warnings, setWarnings] = useState<string[]>([]);
  const [plannerState, setPlannerState] = useState<
    "idle" | "loading" | "planned" | "clarification" | "error"
  >("idle");
  const [plannerMessage, setPlannerMessage] = useState(
    "Describe a command or build one step by step.",
  );
  const [usedFallback, setUsedFallback] = useState(false);
  const [manualType, setManualType] =
    useState<(typeof ACTION_CHOICES)[number]["type"]>("open_url");
  const [manualFields, setManualFields] =
    useState<ManualFields>(defaultManualFields);
  const [manualError, setManualError] = useState("");
  const [importError, setImportError] = useState("");
  const [savedNotice, setSavedNotice] = useState("");
  const [hydrated, setHydrated] = useState(false);
  const [publishReviewOpen, setPublishReviewOpen] = useState(false);
  const [publishReviewed, setPublishReviewed] = useState(false);
  const [publishState, setPublishState] = useState<
    "idle" | "loading" | "success" | "error"
  >("idle");
  const [publishMessage, setPublishMessage] = useState("");
  const [shareResult, setShareResult] = useState<ShareResult | null>(null);
  const [copyNotice, setCopyNotice] = useState("");
  const importInput = useRef<HTMLInputElement>(null);

  const selectedGestureLabel =
    GESTURES.find((gesture) => gesture.id === selectedGesture)?.label ??
    selectedGesture;
  const selectedMapping = profile.mappings.find(
    (mapping) => mapping.gesture === selectedGesture,
  );
  const assignedCount = profile.mappings.length;

  useEffect(() => {
    const loadDraft = window.setTimeout(() => {
      try {
        const saved = window.localStorage.getItem(STORAGE_KEY);
        if (saved) {
          const parsed = readProfile(JSON.parse(saved));
          if (parsed) {
            const initialGesture = parsed.mappings[0]?.gesture ?? "thumbs_up";
            setProfile(parsed);
            setSelectedGesture(initialGesture);
            setPreviewPlan(
              parsed.mappings.find(
                (mapping) => mapping.gesture === initialGesture,
              )?.plan ?? null,
            );
          }
        }
      } catch {
        setSavedNotice(
          "The saved draft was invalid, so a clean profile was opened.",
        );
      } finally {
        setHydrated(true);
      }
    }, 0);
    return () => window.clearTimeout(loadDraft);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(profile));
  }, [hydrated, profile]);

  function selectGesture(nextGesture: Gesture) {
    const mapping = profile.mappings.find(
      (candidate) => candidate.gesture === nextGesture,
    );
    setSelectedGesture(nextGesture);
    setPreviewPlan(mapping?.plan ?? null);
    setWarnings([]);
    setUsedFallback(false);
    setPlannerState("idle");
    setPlannerMessage(
      mapping
        ? `${GESTURES.find((item) => item.id === nextGesture)?.label} is mapped. Review or replace its plan.`
        : "Describe a command or build one step by step.",
    );
  }

  const previewSecretCount = previewPlan?.secretReferences.length ?? 0;
  const publicSummary = useMemo(
    () =>
      profile.mappings.map((mapping) => ({
        gesture:
          GESTURES.find((gesture) => gesture.id === mapping.gesture)?.label ??
          mapping.gesture,
        plan: mapping.plan.name,
        stepCount: mapping.plan.steps.length,
        externalCount: mapping.plan.steps.filter((step) =>
          ["http_request", "discord_webhook", "slack_webhook"].includes(
            step.action.type,
          ),
        ).length,
      })),
    [profile.mappings],
  );

  async function requestPlan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const request = instruction.trim();
    if (!request) {
      setPlannerState("error");
      setPlannerMessage("Describe what should happen before generating a plan.");
      return;
    }
    if (containsSecretMaterial(request)) {
      setPlannerState("error");
      setPlannerMessage(
        "Remove tokens, webhook URLs, passwords, and other secret values. Refer to a configured connection by ID instead.",
      );
      return;
    }

    setPlannerState("loading");
    setPlannerMessage("Building a safe version 1 preview…");
    setWarnings([]);
    setUsedFallback(false);

    try {
      const response = await fetch("/api/v1/plan", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          schemaVersion: 1,
          requestId: crypto.randomUUID(),
          request,
          targetGesture: selectedGesture,
          actionCatalog: ACTION_CATALOG,
        }),
      });
      const payload: unknown = await response.json();
      if (!response.ok) {
        const message =
          isRecord(payload) && typeof payload.message === "string"
            ? payload.message
            : isRecord(payload) &&
                isRecord(payload.error) &&
                typeof payload.error.message === "string"
              ? payload.error.message
              : "Signal could not create a safe version 1 plan from that request.";
        throw new Error(message);
      }
      const parsedResponse = plannerResponseSchema.safeParse(payload);
      if (!parsedResponse.success) {
        throw new Error(
          "The planner response did not pass the frozen version 1 checks.",
        );
      }
      if (parsedResponse.data.status === "needs_clarification") {
        setPlannerState("clarification");
        setPlannerMessage(parsedResponse.data.question);
        return;
      }
      const plan = readPlan(parsedResponse.data.plan);
      if (!plan) {
        throw new Error("The planner response did not pass the version 1 checks.");
      }
      setPreviewPlan(plan);
      setWarnings(parsedResponse.data.warnings);
      const fallback = parsedResponse.data.usedDeterministicFallback;
      setUsedFallback(fallback);
      setPlannerState("planned");
      setPlannerMessage(
        fallback
          ? "Built with Signal’s deterministic fallback. No AI provider was used."
          : "Plan ready to review. Nothing has run.",
      );
    } catch (error) {
      setPlannerState("error");
      setPlannerMessage(
        error instanceof Error
          ? error.message
          : "Signal could not create a safe version 1 plan.",
      );
    }
  }

  function updateManualField<K extends keyof ManualFields>(
    field: K,
    value: ManualFields[K],
  ) {
    setManualFields((current) => ({ ...current, [field]: value }));
  }

  function buildManualAction(): SignalAction | null {
    switch (manualType) {
      case "open_url": {
        const checked = checkPublicHttpsLiteralHost(manualFields.url);
        if (!checked.ok) {
          setManualError(
            "Use a public HTTPS URL without credentials, local hosts, or private addresses.",
          );
          return null;
        }
        return {
          type: "open_url",
          parameters: {
            url: checked.canonicalUrl,
            networkPolicy: "public_https_only",
          },
        };
      }
      case "open_application":
        if (
          !/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(
            manualFields.bundleIdentifier,
          )
        ) {
          setManualError("Enter a bundle identifier such as com.apple.TextEdit.");
          return null;
        }
        return {
          type: "open_application",
          parameters: {
            bundleIdentifier: manualFields.bundleIdentifier,
            applicationName: manualFields.appName.slice(0, 120),
          },
        };
      case "speak_text":
        if (!manualFields.text.trim()) {
          setManualError("Enter the text Signal should speak.");
          return null;
        }
        return {
          type: "speak_text",
          parameters: { text: manualFields.text.trim().slice(0, 500) },
        };
      case "show_notification":
        if (!manualFields.title.trim()) {
          setManualError("Enter a notification title.");
          return null;
        }
        return {
          type: "show_notification",
          parameters: {
            title: manualFields.title.trim().slice(0, 120),
            body: manualFields.body.trim().slice(0, 500),
          },
        };
      case "wait": {
        const durationMs = Number(manualFields.durationMs);
        if (!Number.isInteger(durationMs) || durationMs < 0 || durationMs > 30000) {
          setManualError("Wait duration must be from 0 to 30,000 milliseconds.");
          return null;
        }
        return { type: "wait", parameters: { durationMs } };
      }
      case "media_control":
        return {
          type: "media_control",
          parameters: { command: manualFields.mediaCommand },
        };
      case "set_volume": {
        const percent = Number(manualFields.volume);
        if (!Number.isInteger(percent) || percent < 0 || percent > 100) {
          setManualError("Volume must be a whole number from 0 to 100.");
          return null;
        }
        return { type: "set_volume", parameters: { percent } };
      }
      case "discord_webhook":
        if (
          !IDENTIFIER_PATTERN.test(manualFields.secretRef) ||
          !manualFields.discordMessage.trim()
        ) {
          setManualError(
            "Add a reference ID and the non-sensitive message to send.",
          );
          return null;
        }
        return {
          type: "discord_webhook",
          parameters: {
            secretRef: manualFields.secretRef,
            message: manualFields.discordMessage.trim().slice(0, 1800),
            fallback: "local_receipt",
          },
        };
    }
  }

  function addManualStep() {
    setManualError("");
    const action = buildManualAction();
    if (!action) return;
    if (containsSecretMaterial(action)) {
      setManualError(
        "This step appears to contain a raw secret. Use a secret reference identifier instead.",
      );
      return;
    }
    if (previewPlan && previewPlan.steps.length >= 50) {
      setManualError("Version 1 plans can contain at most 50 steps.");
      return;
    }

    const timeoutMs =
      action.type === "wait"
        ? Math.max(100, Math.min(60000, Number(action.parameters.durationMs) + 1000))
        : 10000;
    const nextStep: PlanStep = {
      id: `step-${Date.now()}`,
      action,
      timeoutMs,
      onFailure: ["discord_webhook", "open_url"].includes(action.type)
        ? "continue"
        : "stop",
      confirmation: actionConfirmation(action.type),
    };
    const currentSteps = previewPlan?.steps ?? [];
    const steps = [...currentSteps, nextStep];
    const secretReferences = [...(previewPlan?.secretReferences ?? [])];
    if (
      action.type === "discord_webhook" &&
      !secretReferences.some((reference) => reference.id === manualFields.secretRef)
    ) {
      secretReferences.push({
        id: manualFields.secretRef,
        provider: "discord",
        purpose: "Discord message for this reviewed gesture command",
        storage: "keychain_or_server_environment",
      });
    }
    setPreviewPlan({
      schemaVersion: 1,
      id: previewPlan?.id ?? `signal.visual.${Date.now()}`,
      name: previewPlan?.name ?? `${selectedGestureLabel} command`,
      description:
        previewPlan?.description ??
        `A visual command mapped to ${selectedGestureLabel.toLowerCase()}.`,
      steps,
      timeoutMs: calculatePlanTimeout(steps),
      onFailure: previewPlan?.onFailure ?? "stop",
      confirmation: previewPlan?.confirmation ?? {
        mode: "first_run",
        reason: "Review every effect before saving and first run.",
      },
      createdSource: "visual",
      secretReferences,
    });
    setPlannerState("planned");
    setPlannerMessage("Manual step added. Nothing has run.");
    setUsedFallback(false);
  }

  function moveStep(index: number, direction: -1 | 1) {
    if (!previewPlan) return;
    const target = index + direction;
    if (target < 0 || target >= previewPlan.steps.length) return;
    const steps = [...previewPlan.steps];
    [steps[index], steps[target]] = [steps[target], steps[index]];
    setPreviewPlan({
      ...previewPlan,
      steps,
      timeoutMs: calculatePlanTimeout(steps),
    });
  }

  function removeStep(index: number) {
    if (!previewPlan) return;
    const steps = previewPlan.steps.filter((_, stepIndex) => stepIndex !== index);
    if (steps.length === 0) {
      setPreviewPlan(null);
      setPlannerState("idle");
      setPlannerMessage("The plan is empty. Add a step or describe a command.");
      return;
    }
    const referencedIds = new Set(
      steps
        .map((step) => step.action.parameters.secretRef)
        .filter((reference): reference is string => typeof reference === "string"),
    );
    setPreviewPlan({
      ...previewPlan,
      steps,
      timeoutMs: calculatePlanTimeout(steps),
      secretReferences: previewPlan.secretReferences.filter((reference) =>
        referencedIds.has(reference.id),
      ),
    });
  }

  function saveMapping() {
    if (!previewPlan) return;
    const cleanPlan = readPlan(previewPlan);
    if (!cleanPlan) {
      setPlannerState("error");
      setPlannerMessage("This plan does not pass the frozen version 1 checks.");
      return;
    }
    const mapping: GestureMapping = {
      gesture: selectedGesture,
      enabled: true,
      holdDurationMs: 600,
      cooldownMs: 900,
      activation: "one_shot",
      allowedBundleIdentifiers: [],
      preferredMode: "commands",
      plan: cleanPlan,
    };
    setProfile((current) => ({
      ...current,
      share: { visibility: "private" },
      mappings: [
        ...current.mappings.filter(
          (candidate) => candidate.gesture !== selectedGesture,
        ),
        mapping,
      ],
    }));
    setShareResult(null);
    setSavedNotice(`${selectedGestureLabel} saved locally. Nothing has run.`);
  }

  function removeMapping() {
    setProfile((current) => ({
      ...current,
      share: { visibility: "private" },
      mappings: current.mappings.filter(
        (mapping) => mapping.gesture !== selectedGesture,
      ),
    }));
    setPreviewPlan(null);
    setShareResult(null);
    setSavedNotice(`${selectedGestureLabel} mapping removed from this draft.`);
  }

  function exportProfile() {
    const clean = readProfile(profile);
    if (!clean) {
      setImportError("This profile cannot be exported until its fields are valid.");
      return;
    }
    const blob = new Blob([JSON.stringify(clean, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `${clean.id}.json`;
    anchor.click();
    URL.revokeObjectURL(url);
    setSavedNotice("Version 1 profile exported. Exporting did not run any action.");
  }

  async function importProfile(event: ChangeEvent<HTMLInputElement>) {
    setImportError("");
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    try {
      if (file.size > 256 * 1024) {
        throw new Error("Profile files must be smaller than 256 KiB.");
      }
      const parsed = readProfile(JSON.parse(await file.text()));
      if (!parsed) {
        throw new Error(
          "This file is not a strict Signal version 1 profile. Unknown fields, actions, and versions are rejected.",
        );
      }
      setProfile(parsed);
      const initialGesture = parsed.mappings[0]?.gesture ?? "thumbs_up";
      setSelectedGesture(initialGesture);
      setPreviewPlan(
        parsed.mappings.find((mapping) => mapping.gesture === initialGesture)
          ?.plan ?? null,
      );
      setShareResult(
        parsed.share.visibility === "unlisted" && parsed.share.shareCode
          ? {
              schemaVersion: 1,
              shareCode: parsed.share.shareCode,
              profileURL: `/p/${parsed.share.shareCode}`,
            }
          : null,
      );
      setSavedNotice(
        "Profile imported and saved locally. Importing did not run any action.",
      );
    } catch (error) {
      setImportError(
        error instanceof Error ? error.message : "The profile could not be read.",
      );
    }
  }

  async function publishProfile() {
    if (!publishReviewed || profile.mappings.length === 0) return;
    const publicProfile: SignalProfile = {
      ...profile,
      share: { visibility: "unlisted" },
    };
    const clean = readProfile(publicProfile);
    if (!clean) {
      setPublishState("error");
      setPublishMessage("The profile does not pass the frozen version 1 checks.");
      return;
    }
    setPublishState("loading");
    setPublishMessage("Publishing the reviewed, non-secret profile…");
    try {
      const response = await fetch("/api/v1/profiles", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ profile: clean }),
      });
      const payload: unknown = await response.json();
      if (
        !response.ok ||
        !isRecord(payload) ||
        payload.schemaVersion !== 1 ||
        typeof payload.shareCode !== "string" ||
        !SHARE_CODE_PATTERN.test(payload.shareCode) ||
        typeof payload.profileURL !== "string"
      ) {
        throw new Error(
          isRecord(payload) && typeof payload.message === "string"
            ? payload.message
            : isRecord(payload) &&
                isRecord(payload.error) &&
                typeof payload.error.message === "string"
              ? payload.error.message
            : "The profile could not be published.",
        );
      }
      const result: ShareResult = {
        schemaVersion: 1,
        shareCode: payload.shareCode,
        profileURL: payload.profileURL,
      };
      setShareResult(result);
      setProfile((current) => ({
        ...current,
        share: { visibility: "unlisted", shareCode: result.shareCode },
      }));
      setPublishState("success");
      setPublishMessage("Unlisted profile published.");
      setPublishReviewOpen(false);
      setPublishReviewed(false);
    } catch (error) {
      setPublishState("error");
      setPublishMessage(
        error instanceof Error
          ? error.message
          : "The profile could not be published.",
      );
    }
  }

  async function copyText(value: string, label: string) {
    try {
      await navigator.clipboard.writeText(value);
      setCopyNotice(`${label} copied.`);
    } catch {
      setCopyNotice(`Could not copy ${label.toLowerCase()}.`);
    }
  }

  return (
    <main className="builder-page">
      <header className="builder-hero">
        <div className="builder-hero-copy">
          <p className="eyebrow">Guest command studio · Schema v1</p>
          <h1>Give every gesture a job.</h1>
          <p className="lede">
            Build, review, and share a Signal profile without an account. The
            browser creates plans; only the Mac app can perform system-wide
            actions.
          </p>
        </div>
        <div className="builder-safety-note" role="note">
          <span className="status-dot" aria-hidden="true" />
          <div>
            <strong>Preview only</strong>
            <p>Nothing on this page runs a Mac command.</p>
          </div>
        </div>
      </header>

      <section className="profile-toolbar" aria-labelledby="profile-heading">
        <div className="profile-fields">
          <div className="section-heading">
            <p className="eyebrow">Profile</p>
            <h2 id="profile-heading">Guest draft</h2>
          </div>
          <label className="field profile-name-field">
            <span>Name</span>
            <input
              value={profile.name}
              maxLength={80}
              onChange={(event) =>
                setProfile((current) => ({
                  ...current,
                  name: event.target.value,
                  share: { visibility: "private" },
                }))
              }
            />
          </label>
          <label className="field profile-description-field">
            <span>Description</span>
            <input
              value={profile.description}
              maxLength={500}
              onChange={(event) =>
                setProfile((current) => ({
                  ...current,
                  description: event.target.value,
                  share: { visibility: "private" },
                }))
              }
            />
          </label>
        </div>

        <fieldset className="mode-picker">
          <legend>Preferred mode</legend>
          <div className="segmented-control">
            {(["touch", "commands", "hybrid"] as const).map((mode) => (
              <label key={mode}>
                <input
                  type="radio"
                  name="preferred-mode"
                  value={mode}
                  checked={profile.preferredMode === mode}
                  onChange={() =>
                    setProfile((current) => ({
                      ...current,
                      preferredMode: mode,
                      share: { visibility: "private" },
                    }))
                  }
                />
                <span>{mode.charAt(0).toUpperCase() + mode.slice(1)}</span>
              </label>
            ))}
          </div>
          {profile.preferredMode === "hybrid" && (
            <label className="field compact-field">
              <span>One gesture in Hybrid</span>
              <select
                value={profile.hybridOneBehavior}
                onChange={(event) =>
                  setProfile((current) => ({
                    ...current,
                    hybridOneBehavior: event.target.value as
                      | "pointer"
                      | "command",
                    share: { visibility: "private" },
                  }))
                }
              >
                <option value="pointer">Keep pointer control</option>
                <option value="command">Use its command</option>
              </select>
            </label>
          )}
        </fieldset>

        <div className="profile-actions">
          <input
            ref={importInput}
            className="visually-hidden"
            type="file"
            accept="application/json,.json"
            onChange={importProfile}
          />
          <button
            className="button button-secondary secondary"
            type="button"
            onClick={() => importInput.current?.click()}
          >
            Import JSON
          </button>
          <button
            className="button button-secondary secondary"
            type="button"
            onClick={exportProfile}
          >
            Export JSON
          </button>
          <button
            className="button button-primary primary"
            type="button"
            disabled={profile.mappings.length === 0}
            onClick={() => {
              setPublishState("idle");
              setPublishMessage("");
              setPublishReviewOpen(true);
            }}
          >
            Review &amp; publish
          </button>
        </div>
        {(savedNotice || importError) && (
          <p
            className={importError ? "form-message error" : "form-message"}
            role={importError ? "alert" : "status"}
          >
            {importError || savedNotice}
          </p>
        )}
      </section>

      <div className="builder-workspace">
        <aside className="gesture-panel" aria-labelledby="gestures-heading">
          <div className="section-heading">
            <p className="eyebrow">Step 1</p>
            <h2 id="gestures-heading">Choose a gesture</h2>
            <p>
              {assignedCount} of 9 assigned. Gesture names remain visible
              alongside their marks.
            </p>
          </div>
          <div className="gesture-grid">
            {GESTURES.map((gesture) => {
              const mapping = profile.mappings.find(
                (candidate) => candidate.gesture === gesture.id,
              );
              return (
                <button
                  key={gesture.id}
                  type="button"
                  className={`gesture-card${
                    selectedGesture === gesture.id ? " selected" : ""
                  }${mapping ? " assigned" : ""}`}
                  aria-pressed={selectedGesture === gesture.id}
                  onClick={() => selectGesture(gesture.id)}
                >
                  <span className="gesture-mark" aria-hidden="true">
                    {gesture.mark}
                  </span>
                  <span className="gesture-name">{gesture.label}</span>
                  <span className="gesture-state">
                    {mapping ? mapping.plan.steps.length + " steps" : "Unassigned"}
                  </span>
                </button>
              );
            })}
          </div>
          {profile.preferredMode === "hybrid" &&
            selectedGesture === "one" &&
            profile.hybridOneBehavior === "pointer" && (
              <p className="inline-warning" role="note">
                Hybrid Mode keeps One for pointer control. Change its behavior
                above to use this command.
              </p>
            )}
        </aside>

        <section className="plan-panel" aria-labelledby="plan-heading">
          <div className="section-heading plan-heading-row">
            <div>
              <p className="eyebrow">Step 2 · {selectedGestureLabel}</p>
              <h2 id="plan-heading">Build the command</h2>
            </div>
            {selectedMapping && <span className="status-chip">Saved locally</span>}
          </div>

          <form className="prompt-card" onSubmit={requestPlan}>
            <label htmlFor="command-instruction">
              Describe what should happen
            </label>
            <textarea
              id="command-instruction"
              value={instruction}
              maxLength={4000}
              rows={4}
              onChange={(event) => setInstruction(event.target.value)}
            />
            <div className="prompt-actions">
              <span>{instruction.length.toLocaleString()} / 4,000</span>
              <button
                className="button button-primary primary"
                type="submit"
                disabled={plannerState === "loading"}
              >
                {plannerState === "loading" ? "Building preview…" : "Generate plan"}
              </button>
            </div>
          </form>

          <div
            className={`planner-status ${plannerState}`}
            role={plannerState === "error" ? "alert" : "status"}
            aria-live="polite"
          >
            <strong>
              {plannerState === "clarification"
                ? "One detail needed"
                : plannerState === "error"
                  ? "Plan not created"
                  : usedFallback
                    ? "Deterministic fallback"
                    : "Plan status"}
            </strong>
            <p>{plannerMessage}</p>
          </div>

          {warnings.length > 0 && (
            <div className="warning-list" role="note">
              <strong>Review these warnings</strong>
              <ul>
                {warnings.map((warning) => (
                  <li key={warning}>{warning}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="timeline-heading">
            <div>
              <h3>Plan preview</h3>
              <p>Every effect stays visible and editable before save.</p>
            </div>
            {previewPlan && (
              <div className="plan-metadata">
                <span>v1</span>
                <span>{previewPlan.steps.length} steps</span>
                <span>{Math.round(previewPlan.timeoutMs / 1000)}s limit</span>
              </div>
            )}
          </div>

          {!previewPlan ? (
            <div className="empty-plan">
              <span className="empty-plan-mark" aria-hidden="true">
                +
              </span>
              <h3>No steps yet</h3>
              <p>Generate a plan above or add a reviewed action below.</p>
            </div>
          ) : (
            <ol className="plan-timeline">
              {previewPlan.steps.map((step, index) => (
                <li className="plan-step" key={step.id}>
                  <span className="step-number" aria-hidden="true">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div className="step-body">
                    <div className="step-title-row">
                      <div>
                        <span className="capability-chip">
                          {capabilityFor(step.action.type)}
                        </span>
                        <h4>{titleForAction(step.action.type)}</h4>
                      </div>
                      <div className="step-actions" aria-label={`Edit step ${index + 1}`}>
                        <button
                          type="button"
                          aria-label={`Move step ${index + 1} up`}
                          disabled={index === 0}
                          onClick={() => moveStep(index, -1)}
                        >
                          ↑
                        </button>
                        <button
                          type="button"
                          aria-label={`Move step ${index + 1} down`}
                          disabled={index === previewPlan.steps.length - 1}
                          onClick={() => moveStep(index, 1)}
                        >
                          ↓
                        </button>
                        <button
                          type="button"
                          aria-label={`Remove step ${index + 1}`}
                          onClick={() => removeStep(index)}
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                    <p className="step-summary">{summarizeAction(step.action)}</p>
                    <dl className="step-facts">
                      <div>
                        <dt>Confirmation</dt>
                        <dd>{step.confirmation.mode.replace("_", " ")}</dd>
                      </div>
                      <div>
                        <dt>Failure</dt>
                        <dd>{step.onFailure}</dd>
                      </div>
                      <div>
                        <dt>Timeout</dt>
                        <dd>{step.timeoutMs / 1000}s</dd>
                      </div>
                    </dl>
                  </div>
                </li>
              ))}
            </ol>
          )}

          {previewPlan && (
            <div className="plan-approval">
              <div>
                <strong>Review before save</strong>
                <p>
                  Saving maps this preview to {selectedGestureLabel}. It still
                  does not run it.
                </p>
              </div>
              <div className="plan-approval-actions">
                {selectedMapping && (
                  <button
                    className="button button-secondary quiet"
                    type="button"
                    onClick={removeMapping}
                  >
                    Remove mapping
                  </button>
                )}
                <button
                  className="button button-primary primary"
                  type="button"
                  onClick={saveMapping}
                >
                  Save to {selectedGestureLabel}
                </button>
              </div>
            </div>
          )}
        </section>

        <aside className="action-picker-panel" aria-labelledby="actions-heading">
          <div className="section-heading">
            <p className="eyebrow">Visual builder</p>
            <h2 id="actions-heading">Add an action</h2>
            <p>Choose from safe version 1 templates.</p>
          </div>

          <div className="action-choice-grid">
            {ACTION_CHOICES.map((choice) => (
              <button
                key={choice.type}
                type="button"
                className={`action-choice${
                  manualType === choice.type ? " selected" : ""
                }`}
                aria-pressed={manualType === choice.type}
                onClick={() => {
                  setManualType(choice.type);
                  setManualError("");
                }}
              >
                <strong>{choice.label}</strong>
                <span>{choice.description}</span>
                <small>{choice.capability}</small>
              </button>
            ))}
          </div>

          <div className="action-fields">
            {manualType === "open_url" && (
              <label className="field">
                <span>Public HTTPS URL</span>
                <input
                  type="url"
                  value={manualFields.url}
                  onChange={(event) => updateManualField("url", event.target.value)}
                />
              </label>
            )}
            {manualType === "open_application" && (
              <>
                <label className="field">
                  <span>Application name</span>
                  <input
                    value={manualFields.appName}
                    maxLength={120}
                    onChange={(event) =>
                      updateManualField("appName", event.target.value)
                    }
                  />
                </label>
                <label className="field">
                  <span>Bundle identifier</span>
                  <input
                    value={manualFields.bundleIdentifier}
                    onChange={(event) =>
                      updateManualField("bundleIdentifier", event.target.value)
                    }
                  />
                </label>
              </>
            )}
            {manualType === "speak_text" && (
              <label className="field">
                <span>Text to speak</span>
                <textarea
                  rows={3}
                  maxLength={500}
                  value={manualFields.text}
                  onChange={(event) => updateManualField("text", event.target.value)}
                />
              </label>
            )}
            {manualType === "show_notification" && (
              <>
                <label className="field">
                  <span>Title</span>
                  <input
                    maxLength={120}
                    value={manualFields.title}
                    onChange={(event) =>
                      updateManualField("title", event.target.value)
                    }
                  />
                </label>
                <label className="field">
                  <span>Body</span>
                  <textarea
                    rows={3}
                    maxLength={500}
                    value={manualFields.body}
                    onChange={(event) =>
                      updateManualField("body", event.target.value)
                    }
                  />
                </label>
              </>
            )}
            {manualType === "wait" && (
              <label className="field">
                <span>Duration in milliseconds</span>
                <input
                  type="number"
                  min={0}
                  max={30000}
                  step={100}
                  value={manualFields.durationMs}
                  onChange={(event) =>
                    updateManualField("durationMs", event.target.value)
                  }
                />
              </label>
            )}
            {manualType === "media_control" && (
              <label className="field">
                <span>Media command</span>
                <select
                  value={manualFields.mediaCommand}
                  onChange={(event) =>
                    updateManualField(
                      "mediaCommand",
                      event.target.value as ManualFields["mediaCommand"],
                    )
                  }
                >
                  <option value="toggle_play_pause">Toggle play / pause</option>
                  <option value="play">Play</option>
                  <option value="pause">Pause</option>
                  <option value="next">Next track</option>
                  <option value="previous">Previous track</option>
                </select>
              </label>
            )}
            {manualType === "set_volume" && (
              <label className="field">
                <span>Volume percentage</span>
                <input
                  type="number"
                  min={0}
                  max={100}
                  step={1}
                  value={manualFields.volume}
                  onChange={(event) =>
                    updateManualField("volume", event.target.value)
                  }
                />
              </label>
            )}
            {manualType === "discord_webhook" && (
              <>
                <label className="field">
                  <span>Secret reference ID</span>
                  <input
                    value={manualFields.secretRef}
                    onChange={(event) =>
                      updateManualField("secretRef", event.target.value)
                    }
                  />
                  <small>
                    An identifier only. Never paste a webhook URL or token.
                  </small>
                </label>
                <label className="field">
                  <span>Non-sensitive message</span>
                  <textarea
                    rows={3}
                    maxLength={1800}
                    value={manualFields.discordMessage}
                    onChange={(event) =>
                      updateManualField("discordMessage", event.target.value)
                    }
                  />
                </label>
              </>
            )}
          </div>
          {manualError && (
            <p className="form-message error" role="alert">
              {manualError}
            </p>
          )}
          <button
            className="button button-secondary secondary full-width"
            type="button"
            onClick={addManualStep}
          >
            Add reviewed step
          </button>

          <div className="action-picker-note" role="note">
            <strong>Why only templates?</strong>
            <p>
              Version 1 rejects shell commands, raw AppleScript, arbitrary
              authorization headers, and raw secret values.
            </p>
          </div>
        </aside>
      </div>

      {shareResult && (
        <section className="share-result" aria-labelledby="share-result-heading">
          <div>
            <p className="eyebrow">Unlisted profile published</p>
            <h2 id="share-result-heading">{shareResult.shareCode}</h2>
            <p>
              Anyone with this link can view the redacted profile. The page
              cannot run its commands.
            </p>
          </div>
          <div className="share-result-actions">
            <button
              className="button button-secondary secondary"
              type="button"
              onClick={() =>
                copyText(shareResult.shareCode, "Share code")
              }
            >
              Copy code
            </button>
            <button
              className="button button-secondary secondary"
              type="button"
              onClick={() => {
                const url = new URL(shareResult.profileURL, window.location.origin);
                void copyText(url.toString(), "Share link");
              }}
            >
              Copy link
            </button>
            <a
              className="button button-primary primary"
              href={shareResult.profileURL}
            >
              View profile
            </a>
          </div>
          <p className="copy-notice" role="status" aria-live="polite">
            {copyNotice}
          </p>
        </section>
      )}

      {publishReviewOpen && (
        <div className="modal-backdrop">
          <section
            className="publish-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="publish-title"
            aria-describedby="publish-description"
          >
            <button
              className="dialog-close"
              type="button"
              aria-label="Close publishing review"
              onClick={() => setPublishReviewOpen(false)}
            >
              ×
            </button>
            <p className="eyebrow">Final review</p>
            <h2 id="publish-title">Make this profile unlisted?</h2>
            <p id="publish-description">
              Anyone with the link can view its redacted content. A share code
              is not authentication.
            </p>

            <dl className="publish-facts">
              <div>
                <dt>Profile</dt>
                <dd>{profile.name}</dd>
              </div>
              <div>
                <dt>Mode</dt>
                <dd>{profile.preferredMode}</dd>
              </div>
              <div>
                <dt>Mappings</dt>
                <dd>{profile.mappings.length} of 9</dd>
              </div>
              <div>
                <dt>Secret references</dt>
                <dd>
                  {profile.mappings.reduce(
                    (count, mapping) =>
                      count + mapping.plan.secretReferences.length,
                    0,
                  )}{" "}
                  identifiers; no values
                </dd>
              </div>
            </dl>

            <div className="public-plan-list">
              {publicSummary.map((summary) => (
                <article key={summary.gesture}>
                  <strong>{summary.gesture}</strong>
                  <span>{summary.plan}</span>
                  <small>
                    {summary.stepCount} steps
                    {summary.externalCount > 0
                      ? ` · ${summary.externalCount} external`
                      : ""}
                  </small>
                </article>
              ))}
            </div>

            <div className="publish-warning" role="note">
              <strong>Review names, URLs, and message text.</strong>
              <p>
                Signal sends no webhook URL, token, password, cookie, or camera
                data in a portable profile.
              </p>
            </div>

            <label className="review-checkbox">
              <input
                type="checkbox"
                checked={publishReviewed}
                onChange={(event) => setPublishReviewed(event.target.checked)}
              />
              <span>
                I reviewed the public summary and it contains no sensitive text.
              </span>
            </label>

            {publishMessage && (
              <p
                className={`form-message${
                  publishState === "error" ? " error" : ""
                }`}
                role={publishState === "error" ? "alert" : "status"}
              >
                {publishMessage}
              </p>
            )}
            <div className="dialog-actions">
              <button
                className="button button-secondary secondary"
                type="button"
                onClick={() => setPublishReviewOpen(false)}
              >
                Keep private
              </button>
              <button
                className="button button-primary primary"
                type="button"
                disabled={!publishReviewed || publishState === "loading"}
                onClick={publishProfile}
              >
                {publishState === "loading"
                  ? "Publishing…"
                  : "Publish unlisted profile"}
              </button>
            </div>
          </section>
        </div>
      )}

      <p className="visually-hidden" aria-live="polite">
        {copyNotice}
      </p>
      <span className="visually-hidden">
        Current preview uses {previewSecretCount} secret reference identifiers.
      </span>
    </main>
  );
}

export default SignalBuilder;
