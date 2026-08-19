import { environment } from "@raycast/api";
import { spawn } from "node:child_process";
import { access, mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { logDiagnostic } from "./diagnostics";
import { DeskConfiguration, validateTarget } from "./model";
import {
  getConfiguration,
  getDeskIdentifier,
  saveDeskIdentifier,
} from "./storage";

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

async function commonArguments(
  configuration: DeskConfiguration,
): Promise<string[]> {
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
  configuration?: DeskConfiguration,
): Promise<NativeEvent> {
  await access(helperPath).catch(async () => {
    const error = new Error(
      "The Bluetooth helper is missing. Run npm run build:native, then restart the extension.",
    );
    await logDiagnostic("error", "native.helper-missing", { command });
    throw error;
  });
  await mkdir(environment.supportPath, { recursive: true });

  const activeConfiguration = configuration ?? (await getConfiguration());
  const args = [
    command,
    ...commandArguments,
    ...(await commonArguments(activeConfiguration)),
  ];
  await logDiagnostic("info", "native.started", {
    command,
    target: commandArguments[0],
  });
  return new Promise((resolve, reject) => {
    const child = spawn(helperPath, args, {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdoutBuffer = "";
    let stderr = "";
    let lastEvent: NativeEvent | undefined;
    let lastProgressLogAt = 0;

    const acceptLine = (line: string) => {
      if (!line.trim()) return;
      try {
        const event = JSON.parse(line) as NativeEvent;
        lastEvent = event;
        if (event.identifier) void saveDeskIdentifier(event.identifier);
        const now = Date.now();
        if (event.event !== "progress" || now - lastProgressLogAt >= 1_000) {
          lastProgressLogAt = now;
          void logDiagnostic(
            event.event === "error" ? "error" : "info",
            "native.event",
            {
              command,
              event: event.event,
              connected: event.connected,
              heightCm: event.heightCm,
              speed: event.speed,
              outcome: event.outcome,
              message: event.message,
            },
          );
        }
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
    child.on("error", (error) => {
      void logDiagnostic("error", "native.spawn-failed", {
        command,
        message: error.message,
      });
      reject(error);
    });
    child.on("close", (code) => {
      acceptLine(stdoutBuffer);
      if (code === 0 && lastEvent) {
        void logDiagnostic("info", "native.completed", { command, code });
        resolve(lastEvent);
        return;
      }
      const fallbackMessage = `The Bluetooth helper exited without completing${code === null ? "." : ` (code ${code}).`}`;
      const message = lastEvent?.message || stderr.trim() || fallbackMessage;
      void logDiagnostic("error", "native.failed", {
        command,
        code,
        message,
      });
      reject(new Error(message));
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
  const configuration = await getConfiguration();
  const target = validateTarget(targetHeight, configuration);
  await clearStopRequest();
  return runNative("move", [String(target)], onEvent, configuration);
}

export async function nudgeDesk(
  direction: "up" | "down",
  onEvent?: (event: NativeEvent) => void,
): Promise<NativeEvent> {
  const configuration = await getConfiguration();
  const delta =
    direction === "up" ? configuration.stepHeight : -configuration.stepHeight;
  await clearStopRequest();
  return runNative("nudge", [String(delta)], onEvent, configuration);
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
