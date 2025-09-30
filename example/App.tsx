import * as Iperf from "expo-iperf";
import { useEffect } from "react";
import { Button, Text, View } from "react-native";

export default function App() {
  useEffect(() => {
    const sub1 = Iperf.addLogListener((l) => {
      console.log({ l });
      // setLines((prev) => [...prev, l].slice(-400))
    });
    const sub2 = Iperf.addStateListener((s) => {
      console.log({ s });
      // setRunning(s === "started")
    });
    Iperf.isRunning().then((r) => console.log({ r }));
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

      <Button title="Start Server" onPress={() => Iperf.start({})} />
      <Button title="Stop Server" onPress={() => Iperf.stop()} />
    </View>
  );
}
