# expo-iperf

An Expo module that brings iperf3 network performance testing to React Native applications. Run network bandwidth tests directly from your mobile app on both iOS and Android.

## Features

- 🚀 Native iperf3 implementation for iOS and Android
- 📊 Real-time bandwidth measurements
- 🔄 Support for both TCP and UDP protocols
- 📱 Event-based API for monitoring test progress
- ⚙️ Configurable test parameters

## Installation

```bash
npm install expo-iperf
```

## Usage

```typescript
import { start, stop, addLogListener, addStateListener } from "expo-iperf";

// Start an iperf server on the device
start({
  port: 5201,
  protocol: "tcp",
  json: true,
});

// Listen to log events
const logSubscription = addLogListener((line) => {
  console.log("iperf output:", line);
});

// Listen to state changes
const stateSubscription = addStateListener((state) => {
  console.log("iperf state:", state); // 'started' | 'stopped' | 'error'
});

// Stop the server
stop();

// Clean up listeners when done
logSubscription.remove();
stateSubscription.remove();
```

## API

### `start(options: StartOptions): void`

Starts an iperf3 server on the device with the specified options.

**Options:**

- `port?: number` - Server port (default: 5201)
- `json?: boolean` - Enable JSON output (default: true)
- `protocol?: 'tcp' | 'udp'` - Protocol to use (default: 'tcp')

### `stop(): void`

Stops the currently running iperf server.

### `isRunning(): boolean`

Returns whether an iperf server is currently running.

### `addLogListener(callback: (line: string) => void): EventSubscription`

Subscribes to log output from the iperf server.

### `addStateListener(callback: (state: StateValue) => void): EventSubscription`

Subscribes to state changes. State can be `'started'`, `'stopped'`, or `'error'`.

## Requirements

- Expo SDK 50+
- iOS 13.0+
- Android API 21+

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
