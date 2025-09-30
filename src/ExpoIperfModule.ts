import { NativeModule, requireNativeModule } from "expo";

import { ExpoIperfModuleEvents, StartOptions } from "./ExpoIperf.types";

declare class ExpoIperfModule extends NativeModule<ExpoIperfModuleEvents> {
  getTheme: () => string;
  setTheme: (theme: string) => void;
  start: (options: StartOptions) => void;
  stop: () => void;
  isRunning(): Promise<boolean>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoIperfModule>("ExpoIperf");
