import * as Iperf from "expo-iperf";
import { useEffect, useState } from "react";
import { Button, ScrollView, Text, View } from "react-native";

type IperfIntervalData = {
  event: "interval";
  data: {
    streams: Array<{
      socket: number;
      start: number;
      end: number;
      seconds: number;
      bytes: number;
      bits_per_second: number;
      omitted: boolean;
      sender: boolean;
    }>;
    sum: {
      start: number;
      end: number;
      seconds: number;
      bytes: number;
      bits_per_second: number;
      omitted: boolean;
      sender: boolean;
    };
  };
};

type IperfEndData = {
  event: "end";
  data: {
    streams: Array<{
      sender: {
        socket: number;
        start: number;
        end: number;
        seconds: number;
        bytes: number;
        bits_per_second: number;
        sender: boolean;
      };
      receiver: {
        socket: number;
        start: number;
        end: number;
        seconds: number;
        bytes: number;
        bits_per_second: number;
        sender: boolean;
      };
    }>;
    sum_sent: {
      start: number;
      end: number;
      seconds: number;
      bytes: number;
      bits_per_second: number;
      sender: boolean;
    };
    sum_received: {
      start: number;
      end: number;
      seconds: number;
      bytes: number;
      bits_per_second: number;
      sender: boolean;
    };
    cpu_utilization_percent: {
      host_total: number;
      host_user: number;
      host_system: number;
      remote_total: number;
      remote_user: number;
      remote_system: number;
    };
  };
};

type IperfEvent = IperfIntervalData | IperfEndData;

export default function App() {
  const [running, setRunning] = useState(false);
  const [logs, setLogs] = useState<string[]>([]);
  const [currentSpeed, setCurrentSpeed] = useState<number | null>(null);
  const [finalResults, setFinalResults] = useState<IperfEndData["data"] | null>(
    null
  );

  useEffect(() => {
    const sub1 = Iperf.addLogListener((l) => {
      console.log({ l });
      setLogs((prev) => [...prev, l].slice(-400));

      try {
        const parsed: IperfEvent = JSON.parse(l);

        if (parsed.event === "interval") {
          // Update current speed during the test
          const speedMbps = parsed.data.sum.bits_per_second / 1_000_000;
          setCurrentSpeed(speedMbps);
        } else if (parsed.event === "end") {
          // Save final results
          setFinalResults(parsed.data);
          const finalSpeedMbps =
            parsed.data.sum_received.bits_per_second / 1_000_000;
          console.log(
            "Test complete! Final speed:",
            finalSpeedMbps.toFixed(2),
            "Mbps"
          );
        }
      } catch (e) {
        // Not JSON or parse error - just a regular log line
        console.log("Non-JSON log:", l);
      }
    });

    const sub2 = Iperf.addStateListener((s) => {
      console.log({ s });
      setRunning(s === "started");
      if (s === "stopped") {
        setCurrentSpeed(null);
      }
    });

    console.log("isRunning", Iperf.isRunning());

    return () => {
      sub1.remove();
      sub2.remove();
    };
  }, []);

  return (
    <View style={{ flex: 1, padding: 20, paddingTop: 60 }}>
      <Text style={{ fontSize: 18, fontWeight: "bold" }}>
        Status: {running ? "Running" : "Stopped"}
      </Text>

      {currentSpeed !== null && (
        <Text style={{ fontSize: 16, marginTop: 10 }}>
          Current Speed: {currentSpeed.toFixed(2)} Mbps
        </Text>
      )}

      {finalResults && (
        <View
          style={{
            marginTop: 20,
            padding: 10,
            backgroundColor: "#f0f0f0",
            borderRadius: 8,
          }}
        >
          <Text style={{ fontSize: 16, fontWeight: "bold" }}>
            Final Results:
          </Text>
          <Text>Duration: {finalResults.sum_received.seconds.toFixed(2)}s</Text>
          <Text>
            Speed:{" "}
            {(finalResults.sum_received.bits_per_second / 1_000_000).toFixed(2)}{" "}
            Mbps
          </Text>
          <Text>
            Total Data:{" "}
            {(finalResults.sum_received.bytes / 1_048_576).toFixed(2)} MB
          </Text>
          <Text>
            CPU Usage:{" "}
            {finalResults.cpu_utilization_percent.host_total.toFixed(1)}%
          </Text>
        </View>
      )}

      <View style={{ marginTop: 20 }}>
        <Button
          title="Start Server"
          onPress={() => {
            setFinalResults(null);
            setCurrentSpeed(null);
            Iperf.start({});
          }}
        />
        <Button title="Stop Server" onPress={() => Iperf.stop()} />
      </View>

      <ScrollView style={{ marginTop: 20, flex: 1 }}>
        <Text style={{ fontSize: 14, fontWeight: "bold" }}>Logs:</Text>
        {logs.map((log, i) => (
          <Text key={i} style={{ fontSize: 10, fontFamily: "monospace" }}>
            {log}
          </Text>
        ))}
      </ScrollView>
    </View>
  );
}
