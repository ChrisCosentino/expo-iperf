import * as Iperf from "expo-iperf";
import { useEffect, useState } from "react";
import { Button, Text, View } from "react-native";

export default function App() {
  const [running, setRunning] = useState(false);
  const [logs, setLogs] = useState<string[]>([]);

  useEffect(() => {
    const sub1 = Iperf.addLogListener((l) => {
      console.log({ l });
      setLogs((prev) => [...prev, l].slice(-400));
    });
    const sub2 = Iperf.addStateListener((s) => {
      console.log({ s });
      setRunning(s === "started");
    });

    console.log("isRunning", Iperf.isRunning());
    // Iperf.isRunning().then((r) => console.log({ r }));
    // Iperf.isRunning().then((r) => {
    //   console.log({ r });
    // });
    return () => {
      sub1.remove();
      sub2.remove();
    };
  }, []);

  return (
    <View style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
      <Text>Theme: {Iperf.getTheme()}</Text>
      <Button title="Set Theme" onPress={() => Iperf.setTheme("dark")} />

      <Text style={{ marginTop: 20 }}>
        Status: {running ? "Running" : "Stopped"}
      </Text>
      <Button title="Start Server" onPress={() => Iperf.start({})} />
      <Button title="Stop Server" onPress={() => Iperf.stop()} />
    </View>
  );
}
