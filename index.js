import { Platform } from "react-native";
import LinearGradientIos from "./index.ios.js";
import LinearGradientAndroid from "./index.android.js";
import LinearGradientWindows from "./index.windows.js";
import LinearGradientNativeComponentRN from "./src/index.js";

export const LinearGradient = Platform.OS === "ios"
  ? LinearGradientIos : Platform.OS === "android"
  ? LinearGradientAndroid : LinearGradientWindows;

export const LinearGradientNativeComponent = LinearGradientNativeComponentRN;

export default LinearGradient;
