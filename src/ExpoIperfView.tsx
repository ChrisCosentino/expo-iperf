import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoIperfViewProps } from './ExpoIperf.types';

const NativeView: React.ComponentType<ExpoIperfViewProps> =
  requireNativeView('ExpoIperf');

export default function ExpoIperfView(props: ExpoIperfViewProps) {
  return <NativeView {...props} />;
}
