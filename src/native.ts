import { environment, getPreferenceValues } from "@raycast/api";
import { spawn } from "node:child_process";
import { access, mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  DeskConfiguration,
  parseHeight,
  validateConfiguration,
  validateTarget,
} from "./model";
import { getDeskIdentifier, saveDeskIdentifier } from "./storage";

type Preferences = {
  deskName: string;
  baseHeight: string;
  minimumHeight: string;
  maximumHeight: string;
  stepHeight: string;
};

export type NativeEvent = {
  event: "status" | "progress" | "complete" | "error";
  connected?: boolean;
  deskName?: string;
  identifier?: string;
  heightCm?: number;
  speed?: number;
  outcome?: "reached" | "stopped";
  message?: string;
};

const helperPath = path.join(environment.assetsPath, "deskctl");
const stopRequestPath = path.join(environment.supportPath, "stop-request");
const movementLockPath = path.join(environment.supportPath, "movement.lock");

export function getConfiguration(): DeskConfiguration {
  const preferences = getPreferenceValues<Preferences>();
  return validateConfiguration({
    deskName: preferences.deskName,
    baseHeight: parseHeight(preferences.baseHeight, "Base Height"),
    minimumHeight: parseHeight(preferences.minimumHeight, "Minimum Height"),
    maximumHeight: parseHeight(preferences.maximumHeight, "Maximum Height"),
    stepHeight: parseHeight(preferences.stepHeight, "Raise and Lower Step"),
  });
}

async function commonArguments(): Promise<string[]> {
  const configuration = getConfiguration();
  const identifier = await getDeskIdentifier();
  const args = [
    "--name",
    configuration.deskName,
    "--base-height",
    String(configuration.baseHeight),
    "--minimum-height",
    String(configuration.minimumHeight),
    "--maximum-height",
    String(configuration.maximumHeight),
    "--cancel-file",
    stopRequestPath,
    "--lock-file",
    movementLockPath,
  ];
  if (identifier) {
    args.push("--identifier", identifier);
  }
  return args;
}

async function runNative(
  command: string,
  commandArguments: string[] = [],
  onEvent?: (event: NativeEvent) => void,
): Promise<NativeEvent> {
  await access(helperPath).catch(() => {
    throw new Error(
      "The Bluetooth helper is missing. Run npm run build:native, then restart the extension.",
    );
  });
  await mkdir(environment.supportPath, { recursive: true });

  const args = [command, ...commandArguments, ...(await commonArguments())];
  return new Promise((resolve, reject) => {
    const child = spawn(helperPath, args, {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdoutBuffer = "";
    let stderr = "";
    let lastEvent: NativeEvent | undefined;

    const acceptLine = (line: string) => {
      if (!line.trim()) return;
      try {
        const event = JSON.parse(line) as NativeEvent;
        lastEvent = event;
        if (event.identifier) void saveDeskIdentifier(event.identifier);
        onEvent?.(event);
      } catch {
        stderr += `${line}\n`;
      }
    };

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      stdoutBuffer += chunk;
      const lines = stdoutBuffer.split("\n");
      stdoutBuffer = lines.pop() ?? "";
      lines.forEach(acceptLine);
    });
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code) => {
      acceptLine(stdoutBuffer);
      if (code === 0 && lastEvent) {
        resolve(lastEvent);
        return;
      }
      const fallbackMessage = `The Bluetooth helper exited without completing${code === null ? "." : ` (code ${code}).`}`;
      reject(new Error(lastEvent?.message || stderr.trim() || fallbackMessage));
    });
  });
}

export async function readDesk(
  onEvent?: (event: NativeEvent) => void,
): Promise<NativeEvent> {
  return runNative("status", [], onEvent);
}

export async function moveDesk(
  targetHeight: number,
  onEvent?: (event: NativeEvent) => void,
): Promise<NativeEvent> {
  const target = validateTarget(targetHeight, getConfiguration());
  await clearStopRequest();
  return runNative("move", [String(target)], onEvent);
}

export async function nudgeDesk(
  direction: "up" | "down",
  onEvent?: (event: NativeEvent) => void,
): Promise<NativeEvent> {
  const configuration = getConfiguration();
  const delta =
    direction === "up" ? configuration.stepHeight : -configuration.stepHeight;
  await clearStopRequest();
  return runNative("nudge", [String(delta)], onEvent);
}

export async function requestStop(): Promise<void> {
  await mkdir(environment.supportPath, { recursive: true });
  await writeFile(stopRequestPath, "stop\n", "utf8");
}

export async function stopDesk(
  onEvent?: (event: NativeEvent) => void,
): Promise<NativeEvent> {
  await requestStop();
  await new Promise((resolve) => setTimeout(resolve, 700));
  return runNative("stop", [], onEvent);
}

async function clearStopRequest(): Promise<void> {
  await rm(stopRequestPath, { force: true });
}
