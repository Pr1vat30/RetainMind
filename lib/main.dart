// ignore_for_file: experimental_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import 'providers/exam_provider.dart';
import 'screens/splash_screen.dart';
import 'services/livekit_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Profilo audio studio ad alta fedeltà (Full Bandwidth Media Playout + Full Duplex Microphone)
  // Apple: playAndRecord con spokenAudio/defaultToSpeaker (voce calda, naturale e profonda, zero effetto citofono)
  // Android: mode normal + streamType music / usageType media per riproduzione Hi-Fi sullo speaker multimediale
  await LiveKitClient.initialize(
    bypassVoiceProcessing: false,
    zeroPlayoutDelay: true,
    initialAudioSessionOptions: kNaturalVoiceAudioOptions,
  );

  if (!kIsWeb) {
    try {
      await AudioManager.instance.setAudioSessionOptions(kNaturalVoiceAudioOptions);
      await AudioManager.instance.setSpeakerOutputPreferred(true, force: true);
    } catch (_) {}
  }

  runApp(const RetainMindApp());
}

class RetainMindApp extends StatelessWidget {
  const RetainMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExamProvider()),
      ],
      child: Consumer<ExamProvider>(
        builder: (context, exam, _) {
          return MaterialApp(
            title: AppConstants.appTitle,
            debugShowCheckedModeBanner: false,
            themeMode: exam.themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
