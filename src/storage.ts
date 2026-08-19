import { LocalStorage } from "@raycast/api";
import { logDiagnostic } from "./diagnostics";
import {
  defaultConfiguration,
  DeskConfiguration,
  DEFAULT_SIT_HEIGHT,
  DEFAULT_STAND_HEIGHT,
  validateConfiguration,
  validateTarget,
} from "./model";

export type PresetName = "sit" | "stand";

const keys = {
  sit: "preset.sit",
  stand: "preset.stand",
  deskIdentifier: "desk.identifier",
  deskStatus: "desk.status",
  safetyAcknowledged: "safety.acknowledged",
  configuration: "desk.configuration",
} as const;

export type DeskSettings = {
  configuration: DeskConfiguration;
  presets: Record<PresetName, number>;
};

export type CachedDeskStatus = {
  heightCm: number;
  deskName?: string;
  updatedAt: number;
};

export async function getPreset(name: PresetName): Promise<number> {
  const value = await LocalStorage.getItem<string>(keys[name]);
  const parsed = value === undefined ? Number.NaN : Number(value);
  if (Number.isFinite(parsed)) {
    return parsed;
  }
  return name === "sit" ? DEFAULT_SIT_HEIGHT : DEFAULT_STAND_HEIGHT;
}

export async function getPresets(): Promise<Record<PresetName, number>> {
  const [sit, stand] = await Promise.all([
    getPreset("sit"),
    getPreset("stand"),
  ]);
  return { sit, stand };
}

export async function savePreset(
  name: PresetName,
  height: number,
): Promise<void> {
  await LocalStorage.setItem(keys[name], String(height));
}

export async function getConfiguration(): Promise<DeskConfiguration> {
  const stored = await LocalStorage.getItem<string>(keys.configuration);
  if (stored === undefined) return defaultConfiguration();

  try {
    const parsed = JSON.parse(stored) as DeskConfiguration;
    return validateConfiguration(parsed);
  } catch (error) {
    const configuration = defaultConfiguration();
    await LocalStorage.setItem(
      keys.configuration,
      JSON.stringify(configuration),
    );
    await logDiagnostic("warning", "settings.invalid-restored", {
      message: error instanceof Error ? error.message : String(error),
    });
    return configuration;
  }
}

export async function saveConfiguration(
  configuration: DeskConfiguration,
): Promise<void> {
  const validated = validateConfiguration(configuration);
  await LocalStorage.setItem(keys.configuration, JSON.stringify(validated));
  await logDiagnostic("info", "settings.saved", {
    baseHeight: validated.baseHeight,
    minimumHeight: validated.minimumHeight,
    maximumHeight: validated.maximumHeight,
    stepHeight: validated.stepHeight,
  });
}

export async function saveSettings(settings: DeskSettings): Promise<void> {
  const configuration = validateConfiguration(settings.configuration);
  const sit = validateTarget(settings.presets.sit, configuration);
  const stand = validateTarget(settings.presets.stand, configuration);
  await Promise.all([
    saveConfiguration(configuration),
    savePreset("sit", sit),
    savePreset("stand", stand),
  ]);
}

export async function restoreDefaultSettings(): Promise<DeskSettings> {
  const settings: DeskSettings = {
    configuration: defaultConfiguration(),
    presets: { sit: DEFAULT_SIT_HEIGHT, stand: DEFAULT_STAND_HEIGHT },
  };
  await saveSettings(settings);
  await logDiagnostic("info", "settings.restored-defaults");
  return settings;
}

export async function getCachedDeskStatus(): Promise<
  CachedDeskStatus | undefined
> {
  const stored = await LocalStorage.getItem<string>(keys.deskStatus);
  if (stored === undefined) return undefined;

  try {
    const status = JSON.parse(stored) as CachedDeskStatus;
    if (
      !Number.isFinite(status.heightCm) ||
      !Number.isFinite(status.updatedAt) ||
      (status.deskName !== undefined && typeof status.deskName !== "string")
    ) {
      return undefined;
    }
    return status;
  } catch {
    return undefined;
  }
}

export async function saveCachedDeskStatus(
  status: CachedDeskStatus,
): Promise<void> {
  await LocalStorage.setItem(keys.deskStatus, JSON.stringify(status));
}

export async function getDeskIdentifier(): Promise<string | undefined> {
  return LocalStorage.getItem<string>(keys.deskIdentifier);
}

export async function saveDeskIdentifier(identifier: string): Promise<void> {
  await LocalStorage.setItem(keys.deskIdentifier, identifier);
}

export async function selectDeskIdentifier(identifier: string): Promise<void> {
  const currentIdentifier = await getDeskIdentifier();
  await saveDeskIdentifier(identifier);
  if (currentIdentifier !== identifier) {
    await LocalStorage.removeItem(keys.deskStatus);
  }
}

export async function forgetDeskIdentifier(): Promise<void> {
  await LocalStorage.removeItem(keys.deskIdentifier);
}

export async function hasAcknowledgedSafety(): Promise<boolean> {
  return (
    (await LocalStorage.getItem<string>(keys.safetyAcknowledged)) === "true"
  );
}

export async function acknowledgeSafety(): Promise<void> {
  await LocalStorage.setItem(keys.safetyAcknowledged, "true");
}
