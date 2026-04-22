declare module 'react-native-linear-gradient' {
  import * as React from 'react';
  import * as ReactNative from 'react-native';

  export interface LinearGradientProps extends ReactNative.ViewProps {
    colors: (string | number)[];
    start?: { x: number; y: number };
    end?: { x: number; y: number };
    locations?: number[];
    useAngle?: boolean;
    angleCenter?: {x: number, y: number};
    angle?: number;
  }

  export interface LinearGradientNativeComponentProps extends Omit<LinearGradientProps, 'start' | 'end'>{
    startPoint?: { x: number; y: number },
    endPoint?: { x: number; y: number },
  }

  export class LinearGradient extends React.Component<LinearGradientProps> {}
  export class LinearGradientNativeComponent extends React.Component<LinearGradientProps> {}

  export default LinearGradient;
}
