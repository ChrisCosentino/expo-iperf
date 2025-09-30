import { NativeModule, requireNativeModule } from 'expo';

import { ExpoIperfModuleEvents } from './ExpoIperf.types';

declare class ExpoIperfModule extends NativeModule<ExpoIperfModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoIperfModule>('ExpoIperf');
