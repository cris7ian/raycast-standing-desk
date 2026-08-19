import { Form } from "@raycast/api";
import { useEffect, useState } from "react";
import {
  defaultConfiguration,
  DEFAULT_SIT_HEIGHT,
  DEFAULT_STAND_HEIGHT,
} from "./model";
import SettingsForm from "./settings-form";
import { DeskSettings, getConfiguration, getPresets } from "./storage";

const defaults: DeskSettings = {
  configuration: defaultConfiguration(),
  presets: { sit: DEFAULT_SIT_HEIGHT, stand: DEFAULT_STAND_HEIGHT },
};

export default function Command() {
  const [settings, setSettings] = useState(defaults);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    void Promise.all([getConfiguration(), getPresets()])
      .then(([configuration, presets]) => {
        setSettings({ configuration, presets });
      })
      .finally(() => setIsLoading(false));
  }, []);

  if (isLoading) {
    return <Form isLoading navigationTitle="Desk Settings" />;
  }

  return (
    <SettingsForm
      initialSettings={settings}
      onSaved={setSettings}
      popAfterSave={false}
    />
  );
}
