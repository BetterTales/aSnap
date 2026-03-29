import 'package:flutter/material.dart';

class LaserSample {
  const LaserSample({
    required this.position,
    required this.timestampSeconds,
    this.strokeId = 0,
  });

  final Offset position;
  final double timestampSeconds;
  final int strokeId;
}

class LaserState extends ChangeNotifier {
  LaserState() {
    _clock.start();
  }

  final Stopwatch _clock = Stopwatch();
  final List<LaserSample> _samples = [];

  List<LaserSample> get samples => List.unmodifiable(_samples);

  bool get hasSamples => _samples.isNotEmpty;

  double nowSeconds() =>
      _clock.elapsedMicroseconds / Duration.microsecondsPerSecond;

  LaserSample? get latestSample => _samples.isEmpty ? null : _samples.last;

  void addSample(
    Offset position, {
    double? timestampSeconds,
    int strokeId = 0,
  }) {
    addSamples([
      LaserSample(
        position: position,
        timestampSeconds: timestampSeconds ?? nowSeconds(),
        strokeId: strokeId,
      ),
    ]);
  }

  void addSamples(Iterable<LaserSample> samples) {
    final pending = samples.toList();
    if (pending.isEmpty) return;
    _samples.addAll(pending);
    notifyListeners();
  }

  bool prune({required double maxAgeSeconds}) {
    if (_samples.isEmpty) return false;
    final cutoff = nowSeconds() - maxAgeSeconds;
    final keepIndex = _samples.indexWhere(
      (sample) => sample.timestampSeconds >= cutoff,
    );
    if (keepIndex == 0) {
      return false;
    }
    if (keepIndex == -1) {
      _samples.clear();
      notifyListeners();
      return true;
    }
    _samples.removeRange(0, keepIndex);
    notifyListeners();
    return true;
  }

  void clear() {
    if (_samples.isEmpty) return;
    _samples.clear();
    notifyListeners();
  }
}
