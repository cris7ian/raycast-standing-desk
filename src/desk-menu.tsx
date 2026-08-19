import {
  Color,
  Icon,
  Keyboard,
  LaunchType,
  MenuBarExtra,
  Toast,
  launchCommand,
  openExtensionPreferences,
  showToast,
} from "@raycast/api";
import { useCallback, useEffect, useState } from "react";
import { formatHeight } from "./model";
import {
  NativeEvent,
  getConfiguration,
  moveDesk,
  nudgeDesk,
  readDesk,
  requestStop,
  stopDesk,
} from "./native";
import { ensureSafetyAcknowledgement } from "./safety";
import { getPresets, PresetName, savePreset } from "./storage";

type DeskState = {
  connected: boolean;
  height?: number;
  name?: string;
};

const initialDeskState: DeskState = { connected: false };

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export default function Command() {
  const configuration = getConfiguration();
  const [desk, setDesk] = useState<DeskState>(initialDeskState);
  const [presets, setPresets] = useState({ sit: 70, stand: 110 });
  const [isLoading, setIsLoading] = useState(true);
  const [activity, setActivity] = useState<string>();
  const [statusError, setStatusError] = useState<string>();

  const acceptEvent = useCallback((event: NativeEvent) => {
    if (event.event === "error") return;
    setDesk((current) => ({
      connected: event.connected ?? current.connected,
      height: event.heightCm ?? current.height,
      name: event.deskName ?? current.name,
    }));
  }, []);

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setStatusError(undefined);
    try {
      const [savedPresets, event] = await Promise.all([
        getPresets(),
        readDesk(acceptEvent),
      ]);
      setPresets(savedPresets);
      acceptEvent(event);
    } catch (error) {
      setStatusError(errorMessage(error));
      setDesk((current) => ({ ...current, connected: false }));
    } finally {
      setIsLoading(false);
    }
  }, [acceptEvent]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function performMove(target: number, label: string) {
    if (!(await ensureSafetyAcknowledgement())) return;

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: `Moving desk to ${label}`,
      message: formatHeight(target),
    });
    setActivity(`Moving to ${label}`);
    setStatusError(undefined);
    try {
      const event = await moveDesk(target, acceptEvent);
      acceptEvent(event);
      toast.style = Toast.Style.Success;
      toast.title =
        event.outcome === "stopped" ? "Desk stopped" : `Desk moved to ${label}`;
      toast.message =
        event.heightCm === undefined ? "" : formatHeight(event.heightCm);
    } catch (error) {
      const message = errorMessage(error);
      setStatusError(message);
      toast.style = Toast.Style.Failure;
      toast.title = "Could not move desk";
      toast.message = message;
    } finally {
      setActivity(undefined);
    }
  }

  async function performNudge(direction: "up" | "down") {
    if (!(await ensureSafetyAcknowledgement())) return;

    const label = direction === "up" ? "Raising desk" : "Lowering desk";
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: label,
    });
    setActivity(label);
    setStatusError(undefined);
    try {
      const event = await nudgeDesk(direction, acceptEvent);
      acceptEvent(event);
      toast.style = Toast.Style.Success;
      toast.title =
        event.outcome === "stopped" ? "Desk stopped" : "Desk adjusted";
      toast.message =
        event.heightCm === undefined ? "" : formatHeight(event.heightCm);
    } catch (error) {
      const message = errorMessage(error);
      setStatusError(message);
      toast.style = Toast.Style.Failure;
      toast.title = "Could not adjust desk";
      toast.message = message;
    } finally {
      setActivity(undefined);
    }
  }

  async function performStop() {
    await requestStop();
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Stopping desk",
    });
    if (activity) {
      toast.style = Toast.Style.Success;
      toast.title = "Stop requested";
      return;
    }

    setActivity("Stopping desk");
    try {
      const event = await stopDesk(acceptEvent);
      acceptEvent(event);
      toast.style = Toast.Style.Success;
      toast.title = "Desk stopped";
      toast.message =
        event.heightCm === undefined ? "" : formatHeight(event.heightCm);
    } catch (error) {
      const message = errorMessage(error);
      setStatusError(message);
      toast.style = Toast.Style.Failure;
      toast.title = "Could not contact desk";
      toast.message = `${message} Use the physical control if needed.`;
    } finally {
      setActivity(undefined);
    }
  }

  async function saveCurrentPosition(name: PresetName) {
    const label = name === "sit" ? "Sit" : "Stand";
    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Reading desk height",
    });
    setActivity(`Saving ${label}`);
    setStatusError(undefined);
    try {
      const event = await readDesk(acceptEvent);
      if (event.heightCm === undefined) {
        throw new Error("The desk did not report its height.");
      }
      acceptEvent(event);
      await savePreset(name, event.heightCm);
      setPresets((current) => ({
        ...current,
        [name]: event.heightCm as number,
      }));
      toast.style = Toast.Style.Success;
      toast.title = `Saved ${label} position`;
      toast.message = formatHeight(event.heightCm);
    } catch (error) {
      const message = errorMessage(error);
      setStatusError(message);
      toast.style = Toast.Style.Failure;
      toast.title = `Could not save ${label} position`;
      toast.message = message;
    } finally {
      setActivity(undefined);
    }
  }

  const topBarTitle =
    desk.height === undefined ? "Desk" : formatHeight(desk.height);
  const statusTitle =
    activity ?? (desk.connected ? "Connected" : "Desk unavailable");
  const statusSubtitle = activity
    ? desk.height === undefined
      ? undefined
      : formatHeight(desk.height)
    : desk.connected
      ? `${desk.name ?? "Desk"}${desk.height === undefined ? "" : ` · ${formatHeight(desk.height)}`}`
      : statusError;
  const actionsDisabled = activity !== undefined;

  return (
    <MenuBarExtra
      icon={Icon.Desktop}
      title={topBarTitle}
      tooltip={
        statusError
          ? `Standing Desk: ${statusError}`
          : `Standing Desk${desk.height === undefined ? "" : ` · ${formatHeight(desk.height)}`}`
      }
      isLoading={isLoading || actionsDisabled}
    >
      <MenuBarExtra.Section>
        <MenuBarExtra.Item
          icon={
            activity
              ? Icon.CircleProgress
              : desk.connected
                ? { source: Icon.CheckCircle, tintColor: Color.Green }
                : { source: Icon.WifiDisabled, tintColor: Color.Red }
          }
          title={statusTitle}
          subtitle={statusSubtitle}
        />
      </MenuBarExtra.Section>

      <MenuBarExtra.Section title="Positions">
        <MenuBarExtra.Item
          icon={Icon.Person}
          title="Sit"
          subtitle={formatHeight(presets.sit)}
          shortcut={{ modifiers: ["cmd"], key: "1" }}
          onAction={
            actionsDisabled
              ? undefined
              : () => void performMove(presets.sit, "Sit")
          }
        />
        <MenuBarExtra.Item
          icon={Icon.PersonCircle}
          title="Stand"
          subtitle={formatHeight(presets.stand)}
          shortcut={{ modifiers: ["cmd"], key: "2" }}
          onAction={
            actionsDisabled
              ? undefined
              : () => void performMove(presets.stand, "Stand")
          }
        />
      </MenuBarExtra.Section>

      <MenuBarExtra.Section title="Adjust">
        <MenuBarExtra.Item
          icon={Icon.ArrowUp}
          title="Raise"
          subtitle={formatHeight(configuration.stepHeight)}
          shortcut={{ modifiers: ["cmd"], key: "arrowUp" }}
          onAction={actionsDisabled ? undefined : () => void performNudge("up")}
        />
        <MenuBarExtra.Item
          icon={Icon.ArrowDown}
          title="Lower"
          subtitle={formatHeight(configuration.stepHeight)}
          shortcut={{ modifiers: ["cmd"], key: "arrowDown" }}
          onAction={
            actionsDisabled ? undefined : () => void performNudge("down")
          }
        />
        <MenuBarExtra.Item
          icon={{ source: Icon.Stop, tintColor: Color.Red }}
          title="Stop"
          shortcut={Keyboard.Shortcut.Common.Pin}
          onAction={() => void performStop()}
        />
      </MenuBarExtra.Section>

      <MenuBarExtra.Section>
        <MenuBarExtra.Submenu icon={Icon.Pin} title="Save Current Position">
          <MenuBarExtra.Item
            title="Save as Sit"
            subtitle={formatHeight(presets.sit)}
            onAction={
              actionsDisabled
                ? undefined
                : () => void saveCurrentPosition("sit")
            }
          />
          <MenuBarExtra.Item
            title="Save as Stand"
            subtitle={formatHeight(presets.stand)}
            onAction={
              actionsDisabled
                ? undefined
                : () => void saveCurrentPosition("stand")
            }
          />
        </MenuBarExtra.Submenu>
        <MenuBarExtra.Item
          icon={Icon.ArrowClockwise}
          title="Refresh Height"
          shortcut={Keyboard.Shortcut.Common.Refresh}
          onAction={actionsDisabled ? undefined : () => void refresh()}
        />
        <MenuBarExtra.Item
          icon={Icon.AppWindow}
          title="Open Desk Manager"
          onAction={() =>
            void launchCommand({
              name: "manage-desk",
              type: LaunchType.UserInitiated,
            })
          }
        />
        <MenuBarExtra.Item
          icon={Icon.Gear}
          title="Preferences…"
          onAction={() => void openExtensionPreferences()}
        />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
