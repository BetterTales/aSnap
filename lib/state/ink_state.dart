import 'package:flutter/material.dart';

import '../utils/path_simplify.dart';
import '../utils/ink_defaults.dart';

class InkStroke {
  const InkStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.isEraser,
    required this.smoothingTolerance,
  });

  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final double smoothingTolerance;

  InkStroke appendPoint(Offset point) {
    return InkStroke(
      points: [...points, point],
      color: color,
      strokeWidth: strokeWidth,
      isEraser: isEraser,
      smoothingTolerance: smoothingTolerance,
    );
  }

  InkStroke withStrokeWidth(double nextWidth) {
    return InkStroke(
      points: points,
      color: color,
      strokeWidth: nextWidth,
      isEraser: isEraser,
      smoothingTolerance: smoothingTolerance,
    );
  }

  InkStroke withPoints(List<Offset> nextPoints) {
    return InkStroke(
      points: nextPoints,
      color: color,
      strokeWidth: strokeWidth,
      isEraser: isEraser,
      smoothingTolerance: smoothingTolerance,
    );
  }
}

class InkState extends ChangeNotifier {
  final List<InkStroke> _strokes = [];
  InkStroke? _activeStroke;

  List<InkStroke> get strokes => List.unmodifiable(_strokes);
  InkStroke? get activeStroke => _activeStroke;

  bool get hasStrokes => _strokes.isNotEmpty || _activeStroke != null;

  void startStroke(
    Offset startPoint, {
    Color? color,
    double? strokeWidth,
    bool isEraser = false,
    double? smoothingTolerance,
  }) {
    _activeStroke = InkStroke(
      points: [startPoint],
      color: color ?? kInkDefaultColor,
      strokeWidth: strokeWidth ?? kInkDefaultStrokeWidth,
      isEraser: isEraser,
      smoothingTolerance: smoothingTolerance ?? kInkDefaultSmoothingTolerance,
    );
    notifyListeners();
  }

  void appendStroke(Offset point) {
    if (_activeStroke == null) return;
    _activeStroke = _activeStroke!.appendPoint(point);
    notifyListeners();
  }

  void updateActiveStrokeWidth(double width) {
    if (_activeStroke == null) return;
    if ((_activeStroke!.strokeWidth - width).abs() < 0.01) return;
    _activeStroke = _activeStroke!.withStrokeWidth(width);
    notifyListeners();
  }

  void finishStroke() {
    if (_activeStroke == null) return;
    final stroke = _activeStroke!;
    _activeStroke = null;

    if (stroke.points.length < 2) {
      notifyListeners();
      return;
    }

    final simplified = simplifyPath(
      stroke.points,
      epsilon: stroke.smoothingTolerance,
    );
    _strokes.add(stroke.withPoints(simplified));
    notifyListeners();
  }

  void cancelStroke() {
    if (_activeStroke == null) return;
    _activeStroke = null;
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    _activeStroke = null;
    notifyListeners();
  }
}
