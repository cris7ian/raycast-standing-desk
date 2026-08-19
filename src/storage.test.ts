import { beforeEach, describe, expect, it, vi } from "vitest";

const values = vi.hoisted(() => new Map<string, string>());
const logDiagnostic = vi.hoisted(() => vi.fn());

vi.mock("@raycast/api", () => ({
  LocalStorage: {
    getItem: vi.fn((key: string) => values.get(key)),
    setItem: vi.fn((key: string, value: string) => {
      values.set(key, value);
    }),
    removeItem: vi.fn((key: string) => {
      values.delete(key);
    }),
  },
}));

vi.mock("./diagnostics", () => ({ logDiagnostic }));

import {
  getCachedDeskStatus,
  getConfiguration,
  getPresets,
  restoreDefaultSettings,
  saveCachedDeskStatus,
  saveConfiguration,
  savePreset,
} from "./storage";

describe("standing desk storage", () => {
  beforeEach(() => {
    values.clear();
    logDiagnostic.mockClear();
  });

  it("uses safe defaults when settings have not been saved", async () => {
    await expect(getConfiguration()).resolves.toEqual({
      deskName: "Desk",
      baseHeight: 62,
      minimumHeight: 62,
      maximumHeight: 127,
      stepHeight: 1,
    });
    await expect(getPresets()).resolves.toEqual({ sit: 70, stand: 110 });
  });

  it("replaces invalid saved settings with safe defaults", async () => {
    values.set(
      "desk.configuration",
      JSON.stringify({
        deskName: "Desk",
        baseHeight: 70,
        minimumHeight: 62,
        maximumHeight: 127,
        stepHeight: 1,
      }),
    );

    await expect(getConfiguration()).resolves.toMatchObject({
      baseHeight: 62,
      minimumHeight: 62,
    });
    expect(logDiagnostic).toHaveBeenCalledWith(
      "warning",
      "settings.invalid-restored",
      expect.objectContaining({
        message: "Base Height cannot exceed Minimum Height.",
      }),
    );
  });

  it("restores configuration and positions without clearing other data", async () => {
    await saveConfiguration({
      deskName: "Office",
      baseHeight: 64,
      minimumHeight: 64,
      maximumHeight: 125,
      stepHeight: 2,
    });
    await savePreset("sit", 75);
    await savePreset("stand", 105);
    values.set("desk.identifier", "kept-identifier");

    await expect(restoreDefaultSettings()).resolves.toEqual({
      configuration: {
        deskName: "Desk",
        baseHeight: 62,
        minimumHeight: 62,
        maximumHeight: 127,
        stepHeight: 1,
      },
      presets: { sit: 70, stand: 110 },
    });
    expect(values.get("desk.identifier")).toBe("kept-identifier");
  });

  it("stores a safe last-known desk status without the Bluetooth identifier", async () => {
    await saveCachedDeskStatus({
      heightCm: 109.8,
      deskName: "Desk 1234",
      updatedAt: 1_775_000_000_000,
    });

    await expect(getCachedDeskStatus()).resolves.toEqual({
      heightCm: 109.8,
      deskName: "Desk 1234",
      updatedAt: 1_775_000_000_000,
    });
    expect(values.get("desk.status")).not.toContain("identifier");
  });

  it("ignores an invalid cached desk status", async () => {
    values.set(
      "desk.status",
      JSON.stringify({ heightCm: "unknown", updatedAt: Date.now() }),
    );

    await expect(getCachedDeskStatus()).resolves.toBeUndefined();
  });
});
