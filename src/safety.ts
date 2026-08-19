import { Alert, confirmAlert } from "@raycast/api";
import { acknowledgeSafety, hasAcknowledgedSafety } from "./storage";

export async function ensureSafetyAcknowledgement(): Promise<boolean> {
  if (await hasAcknowledgedSafety()) {
    return true;
  }

  const confirmed = await confirmAlert({
    title: "Move the physical desk?",
    message:
      "Watch the desk while it moves. Keep people, furniture, cables, and objects clear. Be ready to use the physical control.",
    primaryAction: {
      title: "I Understand",
    },
    dismissAction: {
      title: "Cancel",
      style: Alert.ActionStyle.Cancel,
    },
  });

  if (confirmed) {
    await acknowledgeSafety();
  }
  return confirmed;
}
