import 'package:flutter/foundation.dart';

const kCaptureStyleMinBorderRadius = 0.0;
const kCaptureStyleMaxBorderRadius = 48.0;
const kCaptureStyleMinPadding = 0.0;
const kCaptureStyleMaxPadding = 64.0;

@immutable
class CaptureStyleSettings {
  const CaptureStyleSettings({
    required this.borderRadius,
    required this.padding,
    required this.shadowEnabled,
  });

  const CaptureStyleSettings.defaults()
    : borderRadius = 0,
      padding = 0,
      shadowEnabled = false;

  final double borderRadius;
  final double padding;
  final bool shadowEnabled;

  static CaptureStyleSettings fromJson(Map<String, dynamic> json) {
    final borderRadius = json['borderRadius'];
    final padding = json['padding'];
    final shadowEnabled = json['shadowEnabled'];

    return CaptureStyleSettings(
      borderRadius: borderRadius is num ? borderRadius.toDouble() : 0,
      padding: padding is num ? padding.toDouble() : 0,
      shadowEnabled: shadowEnabled is bool ? shadowEnabled : false,
    ).clamped();
  }

  Map<String, dynamic> toJson() {
    return {
      'borderRadius': borderRadius,
      'padding': padding,
      'shadowEnabled': shadowEnabled,
    };
  }

  CaptureStyleSettings copyWith({
    double? borderRadius,
    double? padding,
    bool? shadowEnabled,
  }) {
    return CaptureStyleSettings(
      borderRadius: borderRadius ?? this.borderRadius,
      padding: padding ?? this.padding,
      shadowEnabled: shadowEnabled ?? this.shadowEnabled,
    );
  }

  CaptureStyleSettings clamped() {
    return CaptureStyleSettings(
      borderRadius: borderRadius.clamp(
        kCaptureStyleMinBorderRadius,
        kCaptureStyleMaxBorderRadius,
      ),
      padding: padding.clamp(kCaptureStyleMinPadding, kCaptureStyleMaxPadding),
      shadowEnabled: shadowEnabled,
    );
  }

  CaptureStyleSettings scaled(double scale) {
    final factor = scale <= 0 ? 1.0 : scale;
    return CaptureStyleSettings(
      borderRadius: borderRadius * factor,
      padding: padding * factor,
      shadowEnabled: shadowEnabled,
    );
  }

  bool get hasVisibleEffect =>
      borderRadius > 0.01 || padding > 0.01 || shadowEnabled;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CaptureStyleSettings &&
        other.borderRadius == borderRadius &&
        other.padding == padding &&
        other.shadowEnabled == shadowEnabled;
  }

  @override
  int get hashCode => Object.hash(borderRadius, padding, shadowEnabled);
}
