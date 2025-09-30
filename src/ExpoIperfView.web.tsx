import * as React from 'react';

import { ExpoIperfViewProps } from './ExpoIperf.types';

export default function ExpoIperfView(props: ExpoIperfViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
