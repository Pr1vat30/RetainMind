import 'dart:math' as math;

/// 3D Vector for head orientation and spherical projection
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);

  double length() => math.sqrt(x * x + y * y + z * z);

  Vec3 normalized() {
    final l = length();
    if (l == 0) return const Vec3(0, 0, 1);
    return Vec3(x / l, y / l, z / l);
  }

  static (Vec3, Vec3) spin(Vec3 u, Vec3 v, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return (
      Vec3(u.x * c + v.x * s, u.y * c + v.y * s, u.z * c + v.z * s),
      Vec3(v.x * c - u.x * s, v.y * c - u.y * s, v.z * c - u.z * s),
    );
  }
}

/// Head gaze orientation: yaw (horizontal), pitch (vertical), roll (head tilt)
class HeadGaze {
  final double yaw;   // degrees, positive = look right
  final double pitch; // degrees, positive = look up
  final double roll;  // degrees, positive = head tilt right

  const HeadGaze({
    required this.yaw,
    required this.pitch,
    required this.roll,
  });

  static const HeadGaze rest = HeadGaze(yaw: 28.49, pitch: 28.62, roll: -13.0);
  static const HeadGaze direct = HeadGaze(yaw: 0.0, pitch: 4.0, roll: 0.0);
  static const HeadGaze thinking = HeadGaze(yaw: -18.0, pitch: 22.0, roll: -12.0);
  static const HeadGaze attentive = HeadGaze(yaw: 6.0, pitch: 8.0, roll: 8.0);
  static const HeadGaze skeptical = HeadGaze(yaw: 12.0, pitch: -6.0, roll: 16.0);
  static const HeadGaze sleepy = HeadGaze(yaw: 0.0, pitch: -14.0, roll: -4.0);
  static const HeadGaze zero = HeadGaze(yaw: 0.0, pitch: 0.0, roll: 0.0);
  static const HeadGaze curious = HeadGaze(yaw: 8.0, pitch: 10.0, roll: 10.0);
  static const HeadGaze glanceLeft = HeadGaze(yaw: -16.0, pitch: 6.0, roll: 4.0);
  static const HeadGaze glanceRight = HeadGaze(yaw: 18.0, pitch: 8.0, roll: -6.0);
  static const HeadGaze ponder = HeadGaze(yaw: -14.0, pitch: 22.0, roll: -10.0);

  HeadGaze operator +(HeadGaze other) => HeadGaze(
        yaw: yaw + other.yaw,
        pitch: pitch + other.pitch,
        roll: roll + other.roll,
      );

  HeadGaze operator -(HeadGaze other) => HeadGaze(
        yaw: yaw - other.yaw,
        pitch: pitch - other.pitch,
        roll: roll - other.roll,
      );

  HeadGaze operator *(double factor) => HeadGaze(
        yaw: yaw * factor,
        pitch: pitch * factor,
        roll: roll * factor,
      );

  HeadGaze offset({double yaw = 0.0, double pitch = 0.0, double roll = 0.0}) {
    return HeadGaze(
      yaw: this.yaw + yaw,
      pitch: this.pitch + pitch,
      roll: this.roll + roll,
    );
  }

  HeadGaze copyWith({double? yaw, double? pitch, double? roll}) {
    return HeadGaze(
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      roll: roll ?? this.roll,
    );
  }

  static HeadGaze lerp(HeadGaze a, HeadGaze b, double t) {
    return HeadGaze(
      yaw: a.yaw + (b.yaw - a.yaw) * t,
      pitch: a.pitch + (b.pitch - a.pitch) * t,
      roll: a.roll + (b.roll - a.roll) * t,
    );
  }
}

/// Position and 2D tangent matrix of one eye on the sphere
class EyePose {
  final double x;
  final double y;
  final double a;
  final double b;
  final double c;
  final double d;
  final double depth;

  const EyePose({
    required this.x,
    required this.y,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.depth,
  });
}

/// Computes the spherical orthographic projection of the two capsule eyes
/// Measured directly off the x.ai avatar frames in `jeremy-prt/bloub`.
(EyePose, EyePose) computeEyePoses(
  HeadGaze gaze,
  double radius, {
  double eyeSplitDeg = 15.46,
}) {
  double degToRad(double d) => d * math.pi / 180.0;

  Vec3 f = const Vec3(0, 0, 1);
  Vec3 right = const Vec3(1, 0, 0);
  Vec3 down = const Vec3(0, 1, 0);

  // Yaw: forward swings to right
  (f, right) = Vec3.spin(f, right, degToRad(gaze.yaw));
  // Pitch: forward swings up (opposite of down)
  (down, f) = Vec3.spin(down, f, degToRad(gaze.pitch));
  // Roll: right and down rotate around forward
  (right, down) = Vec3.spin(right, down, degToRad(gaze.roll));

  EyePose makeEye(double angleDeg) {
    // Rotate center along horizontal tangent
    final (eyeF, _) = Vec3.spin(f, right, degToRad(angleDeg));
    // Tangent vectors on sphere surface
    final eyeRight = Vec3(
      right.x - eyeF.x * (right.x * eyeF.x + right.y * eyeF.y + right.z * eyeF.z),
      right.y - eyeF.y * (right.x * eyeF.x + right.y * eyeF.y + right.z * eyeF.z),
      right.z - eyeF.z * (right.x * eyeF.x + right.y * eyeF.y + right.z * eyeF.z),
    ).normalized();

    final eyeDown = Vec3(
      eyeF.y * eyeRight.z - eyeF.z * eyeRight.y,
      eyeF.z * eyeRight.x - eyeF.x * eyeRight.z,
      eyeF.x * eyeRight.y - eyeF.y * eyeRight.x,
    ).normalized();

    return EyePose(
      x: eyeF.x * radius,
      y: eyeF.y * radius,
      a: eyeRight.x,
      b: eyeRight.y,
      c: eyeDown.x,
      d: eyeDown.y,
      depth: eyeF.z,
    );
  }

  // Inner eye (-split) and Outer eye (+split)
  final eye0 = makeEye(-eyeSplitDeg);
  final eye1 = makeEye(eyeSplitDeg);

  return (eye0, eye1);
}
