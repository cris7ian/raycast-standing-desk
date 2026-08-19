import { LocalStorage } from "@raycast/api";
import { DEFAULT_SIT_HEIGHT, DEFAULT_STAND_HEIGHT } from "./model";

export type PresetName = "sit" | "stand";

const keys = {
  sit: "preset.sit",
  stand: "preset.stand",
  deskIdentifier: "desk.identifier",
  safetyAcknowledged: "safety.acknowledged",
} as const;

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

export async function getDeskIdentifier(): Promise<string | undefined> {
  return LocalStorage.getItem<string>(keys.deskIdentifier);
}

export async function saveDeskIdentifier(identifier: string): Promise<void> {
  await LocalStorage.setItem(keys.deskIdentifier, identifier);
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
