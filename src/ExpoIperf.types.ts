export type StateValue = "started" | "stopped" | "error";

export type LogEvent = { line: string };
export type StateEvent = { value: StateValue };

export type ExpoIperfModuleEvents = {
  log: (event: LogEvent) => void;
  state: (event: StateEvent) => void;
};

export type StartOptions = {
  port?: number; // default 5201
  json?: boolean; // default true
  protocol?: "tcp" | "udp"; // default 'tcp'
};
