import {
  Action,
  ActionPanel,
  Alert,
  confirmAlert,
  Form,
  Icon,
  showToast,
  Toast,
  useNavigation,
} from "@raycast/api";
import { useState } from "react";
import { parseHeight, validateConfiguration, validateTarget } from "./model";
import { DeskSettings, restoreDefaultSettings, saveSettings } from "./storage";

type SettingsValues = {
  deskName: string;
  baseHeight: string;
  minimumHeight: string;
  maximumHeight: string;
  stepHeight: string;
  sitHeight: string;
  standHeight: string;
};

function formValues(settings: DeskSettings): SettingsValues {
  return {
    deskName: settings.configuration.deskName,
    baseHeight: String(settings.configuration.baseHeight),
    minimumHeight: String(settings.configuration.minimumHeight),
    maximumHeight: String(settings.configuration.maximumHeight),
    stepHeight: String(settings.configuration.stepHeight),
    sitHeight: String(settings.presets.sit),
    standHeight: String(settings.presets.stand),
  };
}

export default function SettingsForm({
  initialSettings,
  onSaved,
  popAfterSave = true,
}: {
  initialSettings: DeskSettings;
  onSaved: (settings: DeskSettings) => void;
  popAfterSave?: boolean;
}) {
  const { pop } = useNavigation();
  const [values, setValues] = useState(() => formValues(initialSettings));
  const [error, setError] = useState<string>();

  function update(name: keyof SettingsValues, value: string) {
    setValues((current) => ({ ...current, [name]: value }));
    setError(undefined);
  }

  function parseSettings(): DeskSettings {
    const configuration = validateConfiguration({
      deskName: values.deskName,
      baseHeight: parseHeight(values.baseHeight, "Base Height"),
      minimumHeight: parseHeight(values.minimumHeight, "Minimum Height"),
      maximumHeight: parseHeight(values.maximumHeight, "Maximum Height"),
      stepHeight: parseHeight(values.stepHeight, "Raise and Lower Step"),
    });
    return {
      configuration,
      presets: {
        sit: validateTarget(
          parseHeight(values.sitHeight, "Sit Height"),
          configuration,
        ),
        stand: validateTarget(
          parseHeight(values.standHeight, "Stand Height"),
          configuration,
        ),
      },
    };
  }

  async function submit() {
    try {
      const settings = parseSettings();
      await saveSettings(settings);
      onSaved(settings);
      if (popAfterSave) pop();
      await showToast({
        style: Toast.Style.Success,
        title: "Saved desk settings",
      });
    } catch (submissionError) {
      setError(
        submissionError instanceof Error
          ? submissionError.message
          : String(submissionError),
      );
    }
  }

  async function restore() {
    const confirmed = await confirmAlert({
      title: "Restore default settings?",
      message:
        "This resets desk limits, adjustment step, and Sit and Stand positions. It keeps the connected desk and safety acknowledgement.",
      primaryAction: {
        title: "Restore Defaults",
        style: Alert.ActionStyle.Destructive,
      },
      dismissAction: {
        title: "Cancel",
        style: Alert.ActionStyle.Cancel,
      },
    });
    if (!confirmed) return;

    const settings = await restoreDefaultSettings();
    setValues(formValues(settings));
    setError(undefined);
    onSaved(settings);
    await showToast({
      style: Toast.Style.Success,
      title: "Restored default settings",
      message: "Sit 70 cm · Stand 110 cm · Range 62–127 cm",
    });
  }

  return (
    <Form
      navigationTitle="Desk Settings"
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Save Settings"
            icon={Icon.Checkmark}
            onSubmit={submit}
          />
          <Action
            title="Restore Default Settings"
            icon={Icon.ArrowCounterClockwise}
            style={Action.Style.Destructive}
            onAction={restore}
          />
        </ActionPanel>
      }
    >
      <Form.TextField
        id="deskName"
        title="Bluetooth Name"
        value={values.deskName}
        onChange={(value) => update("deskName", value)}
      />
      <Form.Separator />
      <Form.TextField
        id="baseHeight"
        title="Base Height"
        value={values.baseHeight}
        onChange={(value) => update("baseHeight", value)}
      />
      <Form.TextField
        id="minimumHeight"
        title="Minimum Height"
        value={values.minimumHeight}
        onChange={(value) => update("minimumHeight", value)}
      />
      <Form.TextField
        id="maximumHeight"
        title="Maximum Height"
        value={values.maximumHeight}
        onChange={(value) => update("maximumHeight", value)}
      />
      <Form.TextField
        id="stepHeight"
        title="Raise and Lower Step"
        value={values.stepHeight}
        onChange={(value) => update("stepHeight", value)}
      />
      <Form.Separator />
      <Form.TextField
        id="sitHeight"
        title="Sit Height"
        value={values.sitHeight}
        onChange={(value) => update("sitHeight", value)}
      />
      <Form.TextField
        id="standHeight"
        title="Stand Height"
        value={values.standHeight}
        onChange={(value) => update("standHeight", value)}
      />
      <Form.Description
        title={error ? "Cannot Save" : "Defaults"}
        text={
          error ??
          "Desk · base 62 cm · range 62–127 cm · step 1 cm · Sit 70 cm · Stand 110 cm"
        }
      />
    </Form>
  );
}
