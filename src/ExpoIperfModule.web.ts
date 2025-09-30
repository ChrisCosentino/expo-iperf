import { registerWebModule, NativeModule } from 'expo';

import { ExpoIperfModuleEvents } from './ExpoIperf.types';

class ExpoIperfModule extends NativeModule<ExpoIperfModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
}

export default registerWebModule(ExpoIperfModule, 'ExpoIperfModule');
