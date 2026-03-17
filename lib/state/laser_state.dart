import 'package:flutter/material.dart';

class LaserSample {
  const LaserSample({required this.position, required this.timestampSeconds});

  final Offset position;
  final double timestampSeconds;
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

  void addSample(Offset position, {double? timestampSeconds}) {
    addSamples([
      LaserSample(
        position: position,
        timestampSeconds: timestampSeconds ?? nowSeconds(),
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
    var removed = 0;
    while (_samples.isNotEmpty && _samples.first.timestampSeconds < cutoff) {
      _samples.removeAt(0);
      removed += 1;
    }
    if (removed > 0) {
      notifyListeners();
      return true;
    }
    return false;
  }

  void clear() {
    if (_samples.isEmpty) return;
    _samples.clear();
    notifyListeners();
  }
}
