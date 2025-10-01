import type { EventSubscription } from "expo-modules-core";
import ExpoIperfModule from "./ExpoIperfModule";
import type { StartOptions, StateValue } from "./ExpoIperf.types";

// Export types for users
export type { StartOptions, StateValue } from "./ExpoIperf.types";

export function getTheme(): string {
  return ExpoIperfModule.getTheme();
}

export function setTheme(theme: string) {
  return ExpoIperfModule.setTheme(theme);
}

export function start(options: StartOptions) {
  return ExpoIperfModule.start(options);
}

export function stop() {
  return ExpoIperfModule.stop();
}

export function isRunning(): boolean {
  return ExpoIperfModule.isRunning();
}

export function addLogListener(cb: (line: string) => void): EventSubscription {
  return ExpoIperfModule.addListener("log", (e) => cb(e.line));
}

export function addStateListener(
  cb: (s: StateValue) => void
): EventSubscription {
  return ExpoIperfModule.addListener("state", (e) => cb(e.value));
}
