import 'avatar_math.dart';

class AvatarEyeConfig {
  final double width;  // fraction of sphere radius (standard ~0.186)
  final double height; // fraction of sphere radius (standard ~0.412)
  final double open;   // 1.0 = open, 0.0 = fully blinked
  final double tilt;   // tilt in degrees (mirrored for expressions)
  final double arch;   // curved crescent curvature (0.0 = capsule, >0 = happy crescent, <0 = skeptic)

  const AvatarEyeConfig({
    this.width = 0.186,
    this.height = 0.412,
    this.open = 1.0,
    this.tilt = 0.0,
    this.arch = 0.0,
  });

  AvatarEyeConfig copyWith({
    double? width,
    double? height,
    double? open,
    double? tilt,
    double? arch,
  }) {
    return AvatarEyeConfig(
      width: width ?? this.width,
      height: height ?? this.height,
      open: open ?? this.open,
      tilt: tilt ?? this.tilt,
      arch: arch ?? this.arch,
    );
  }

  static AvatarEyeConfig lerp(AvatarEyeConfig a, AvatarEyeConfig b, double t) {
    return AvatarEyeConfig(
      width: a.width + (b.width - a.width) * t,
      height: a.height + (b.height - a.height) * t,
      open: a.open + (b.open - a.open) * t,
      tilt: a.tilt + (b.tilt - a.tilt) * t,
      arch: a.arch + (b.arch - a.arch) * t,
    );
  }
}

enum AvatarAgentMood {
  idle,
  listening,
  thinking,
  speaking,
  scaffolding,
  narrowing,
  collision,
  paused,
}

/// Transient micro-gestures that make the avatar expressive and alive
enum AvatarGesture {
  none,
  nod,         // Affirmative listening nod
  shake,       // Wonder / subtle denial shake
  perk,        // Cheerful bounce & happy eyes on tap / greeting
  curiousTilt, // Inquisitive head tilt
  ponder,      // Thoughtful gaze & slight squint
  wink,        // Playful wink with one eye and head tilt
}

class AvatarPose {
  final HeadGaze gaze;
  final AvatarEyeConfig leftEye;
  final AvatarEyeConfig rightEye;
  final double bodyScaleX;
  final double bodyScaleY;
  final double floatOffset;
  final bool hasOrbitRing;
  final double glowIntensity;

  const AvatarPose({
    required this.gaze,
    required this.leftEye,
    required this.rightEye,
    this.bodyScaleX = 1.0,
    this.bodyScaleY = 1.0,
    this.floatOffset = 0.0,
    this.hasOrbitRing = false,
    this.glowIntensity = 1.0,
  });

  AvatarPose copyWith({
    HeadGaze? gaze,
    AvatarEyeConfig? leftEye,
    AvatarEyeConfig? rightEye,
    double? bodyScaleX,
    double? bodyScaleY,
    double? floatOffset,
    bool? hasOrbitRing,
    double? glowIntensity,
  }) {
    return AvatarPose(
      gaze: gaze ?? this.gaze,
      leftEye: leftEye ?? this.leftEye,
      rightEye: rightEye ?? this.rightEye,
      bodyScaleX: bodyScaleX ?? this.bodyScaleX,
      bodyScaleY: bodyScaleY ?? this.bodyScaleY,
      floatOffset: floatOffset ?? this.floatOffset,
      hasOrbitRing: hasOrbitRing ?? this.hasOrbitRing,
      glowIntensity: glowIntensity ?? this.glowIntensity,
    );
  }

  static AvatarPose forMood(AvatarAgentMood mood) {
    switch (mood) {
      case AvatarAgentMood.listening:
        return const AvatarPose(
          gaze: HeadGaze(yaw: 4.0, pitch: 4.0, roll: 8.0),
          leftEye: AvatarEyeConfig(width: 0.195, height: 0.45, open: 1.0, tilt: 2.0),
          rightEye: AvatarEyeConfig(width: 0.195, height: 0.45, open: 1.0, tilt: -2.0),
          bodyScaleX: 1.02,
          bodyScaleY: 0.98,
          floatOffset: -3.0,
          hasOrbitRing: false,
        );

      case AvatarAgentMood.thinking:
        return const AvatarPose(
          gaze: HeadGaze(yaw: -16.0, pitch: 20.0, roll: -10.0),
          leftEye: AvatarEyeConfig(width: 0.175, height: 0.36, open: 0.85, tilt: 4.0),
          rightEye: AvatarEyeConfig(width: 0.175, height: 0.36, open: 0.85, tilt: -4.0),
          bodyScaleX: 0.99,
          bodyScaleY: 1.02,
          floatOffset: -5.0,
          hasOrbitRing: true,
        );

      case AvatarAgentMood.speaking:
        return const AvatarPose(
          gaze: HeadGaze(yaw: 1.0, pitch: 2.0, roll: -4.0),
          leftEye: AvatarEyeConfig(width: 0.190, height: 0.43, open: 1.0, tilt: 0.0),
          rightEye: AvatarEyeConfig(width: 0.190, height: 0.43, open: 1.0, tilt: 0.0),
          bodyScaleX: 1.04,
          bodyScaleY: 0.97,
          floatOffset: 2.0,
          hasOrbitRing: false,
        );

      case AvatarAgentMood.scaffolding:
        return const AvatarPose(
          gaze: HeadGaze(yaw: 2.0, pitch: 6.0, roll: 6.0),
          leftEye: AvatarEyeConfig(width: 0.20, height: 0.42, open: 1.0, tilt: -6.0),
          rightEye: AvatarEyeConfig(width: 0.20, height: 0.42, open: 1.0, tilt: 6.0),
          bodyScaleX: 1.02,
          bodyScaleY: 1.01,
          floatOffset: -2.0,
          hasOrbitRing: false,
        );

      case AvatarAgentMood.narrowing:
        return const AvatarPose(
          gaze: HeadGaze(yaw: 0.0, pitch: -2.0, roll: 0.0),
          leftEye: AvatarEyeConfig(width: 0.17, height: 0.32, open: 0.9, tilt: 8.0),
          rightEye: AvatarEyeConfig(width: 0.17, height: 0.32, open: 0.9, tilt: -8.0),
          bodyScaleX: 1.0,
          bodyScaleY: 1.0,
          floatOffset: 0.0,
          hasOrbitRing: false,
        );

      case AvatarAgentMood.collision:
        return const AvatarPose(
          gaze: HeadGaze(yaw: 8.0, pitch: 10.0, roll: 14.0),
          // One eye raised higher (arched eyebrow effect)
          leftEye: AvatarEyeConfig(width: 0.18, height: 0.36, open: 0.85, tilt: 5.0),
          rightEye: AvatarEyeConfig(width: 0.21, height: 0.48, open: 1.0, tilt: -10.0),
          bodyScaleX: 0.98,
          bodyScaleY: 1.03,
          floatOffset: -4.0,
          hasOrbitRing: false,
        );

      case AvatarAgentMood.paused:
        return const AvatarPose(
          gaze: HeadGaze(yaw: 0.0, pitch: -12.0, roll: -3.0),
          leftEye: AvatarEyeConfig(width: 0.18, height: 0.12, open: 0.30, tilt: 0.0),
          rightEye: AvatarEyeConfig(width: 0.18, height: 0.12, open: 0.30, tilt: 0.0),
          bodyScaleX: 0.98,
          bodyScaleY: 0.98,
          floatOffset: 4.0,
          hasOrbitRing: false,
        );

      case AvatarAgentMood.idle:
        return const AvatarPose(
          gaze: HeadGaze.rest,
          leftEye: AvatarEyeConfig(width: 0.186, height: 0.412, open: 1.0, tilt: 0.0),
          rightEye: AvatarEyeConfig(width: 0.186, height: 0.412, open: 1.0, tilt: 0.0),
          bodyScaleX: 1.0,
          bodyScaleY: 1.0,
          floatOffset: 0.0,
          hasOrbitRing: false,
        );
    }
  }

  static AvatarPose lerp(AvatarPose a, AvatarPose b, double t) {
    return AvatarPose(
      gaze: HeadGaze.lerp(a.gaze, b.gaze, t),
      leftEye: AvatarEyeConfig.lerp(a.leftEye, b.leftEye, t),
      rightEye: AvatarEyeConfig.lerp(a.rightEye, b.rightEye, t),
      bodyScaleX: a.bodyScaleX + (b.bodyScaleX - a.bodyScaleX) * t,
      bodyScaleY: a.bodyScaleY + (b.bodyScaleY - a.bodyScaleY) * t,
      floatOffset: a.floatOffset + (b.floatOffset - a.floatOffset) * t,
      hasOrbitRing: t > 0.5 ? b.hasOrbitRing : a.hasOrbitRing,
      glowIntensity: a.glowIntensity + (b.glowIntensity - a.glowIntensity) * t,
    );
  }
}
