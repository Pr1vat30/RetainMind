import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retain_mind/widgets/avatar/avatar_math.dart';
import 'package:retain_mind/widgets/avatar/avatar_models.dart';
import 'package:retain_mind/widgets/avatar/grok_avatar.dart';

void main() {
  group('Avatar math & model tests', () {
    test('AvatarPose returns correct values for all moods', () {
      for (final mood in AvatarAgentMood.values) {
        final pose = AvatarPose.forMood(mood);
        expect(pose.bodyScaleX, greaterThan(0.0));
        expect(pose.bodyScaleY, greaterThan(0.0));
        expect(pose.leftEye.height, greaterThan(0.0));
        expect(pose.rightEye.height, greaterThan(0.0));
      }
    });

    test('AvatarPose.lerp smoothly interpolates', () {
      final idle = AvatarPose.forMood(AvatarAgentMood.idle);
      final speaking = AvatarPose.forMood(AvatarAgentMood.speaking);

      final mid = AvatarPose.lerp(idle, speaking, 0.5);
      expect(mid.gaze.yaw, closeTo((idle.gaze.yaw + speaking.gaze.yaw) / 2, 0.001));
      expect(mid.bodyScaleX, closeTo((idle.bodyScaleX + speaking.bodyScaleX) / 2, 0.001));
      expect(mid.bodyScaleY, closeTo((idle.bodyScaleY + speaking.bodyScaleY) / 2, 0.001));
    });

    test('computeEyePoses projects 3D coords onto sphere', () {
      final pose = AvatarPose.forMood(AvatarAgentMood.idle);
      final (leftEye, rightEye) = computeEyePoses(
        pose.gaze,
        80.0,
      );

      // Left eye is horizontally to the left of right eye
      expect(leftEye.x, lessThan(rightEye.x));
      expect(leftEye.depth, greaterThan(0));
      expect(rightEye.depth, greaterThan(0));
    });

    test('HeadGaze operators and offset calculation', () {
      const g1 = HeadGaze(yaw: 10.0, pitch: 5.0, roll: 2.0);
      const g2 = HeadGaze(yaw: 5.0, pitch: -3.0, roll: 1.0);

      final added = g1 + g2;
      expect(added.yaw, equals(15.0));
      expect(added.pitch, equals(2.0));
      expect(added.roll, equals(3.0));

      final subtracted = g1 - g2;
      expect(subtracted.yaw, equals(5.0));
      expect(subtracted.pitch, equals(8.0));
      expect(subtracted.roll, equals(1.0));

      final scaled = g1 * 2.0;
      expect(scaled.yaw, equals(20.0));
      expect(scaled.pitch, equals(10.0));
      expect(scaled.roll, equals(4.0));

      final offsetGaze = g1.offset(yaw: -2.0, pitch: 3.0, roll: -1.0);
      expect(offsetGaze.yaw, equals(8.0));
      expect(offsetGaze.pitch, equals(8.0));
      expect(offsetGaze.roll, equals(1.0));
    });

    test('AvatarEyeConfig and AvatarPose support expressive properties', () {
      const eye = AvatarEyeConfig(arch: 0.5);
      expect(eye.arch, equals(0.5));

      final lerpedEye = AvatarEyeConfig.lerp(
        const AvatarEyeConfig(arch: 0.0),
        const AvatarEyeConfig(arch: 1.0),
        0.5,
      );
      expect(lerpedEye.arch, closeTo(0.5, 0.001));

      final idle = AvatarPose.forMood(AvatarAgentMood.idle);
      final withGlow = idle.copyWith(glowIntensity: 1.5);
      expect(withGlow.glowIntensity, equals(1.5));
    });
  });

  group('GrokAvatar widget tests', () {
    testWidgets('GrokAvatar mounts and updates mood without timer leaks',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: GrokAvatar(
                mood: AvatarAgentMood.listening,
                size: 200,
                isListening: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(GrokAvatar), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Switch mood
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: GrokAvatar(
                mood: AvatarAgentMood.speaking,
                size: 200,
                isSpeaking: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Dispose widget and verify no pending timer assertions
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('GrokAvatar responds to tap gestures without crashing',
        (WidgetTester tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GrokAvatar(
                mood: AvatarAgentMood.idle,
                size: 200,
                onTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byType(GrokAvatar), findsOneWidget);
      await tester.tap(find.byType(GrokAvatar));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tapped, isTrue);

      // Clean disposal
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
