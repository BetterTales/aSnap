const int kDefaultCaptureDelaySeconds = 0;
const List<int> kCaptureDelayPresetSeconds = [0, 3, 5, 10];

int normalizeCaptureDelaySeconds(int seconds) {
  return kCaptureDelayPresetSeconds.contains(seconds)
      ? seconds
      : kDefaultCaptureDelaySeconds;
}
