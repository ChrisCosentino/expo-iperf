// import { EventEmitter } from "expo";
// import { StartOptions, StateValue } from "./ExpoIperf.types";
// import ExpoIperfModule from "./ExpoIperfModule";
// // import { EventSubscription } from "expo-modules-core";
// import type { Subscription } from "expo-modules-core";

import { EventEmitter } from "expo-modules-core";
import type { Subscription } from "expo-modules-core";
import ExpoIperfModule from "./ExpoIperfModule";
import type { StartOptions, StateValue } from "./ExpoIperf.types";

const emitter = new EventEmitter(ExpoIperfModule as any);

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

export function isRunning(): Promise<boolean> {
  return ExpoIperfModule.isRunning();
}

export function addLogListener(cb: (line: string) => void): Subscription {
  return emitter.addListener<{ line: string }>("log", (e) => cb(e.line));
}

export function addStateListener(cb: (s: StateValue) => void): Subscription {
  return emitter.addListener<{ value: StateValue }>("state", (e) =>
    cb(e.value)
  );
}
