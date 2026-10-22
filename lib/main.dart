// ignore_for_file: experimental_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import 'providers/exam_provider.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Profilo audio studio ad alta fedeltà (Full Bandwidth Media Playout + Full Duplex Microphone)
  // Apple: playAndRecord con spokenAudio/defaultToSpeaker (voce calda, naturale e profonda, zero effetto citofono)
  // Android: inCommunication per il microfono + streamType.music / usageType.media per riproduzione Hi-Fi non robotica
  await LiveKitClient.initialize(
    bypassVoiceProcessing: false,
    zeroPlayoutDelay: false,
    initialAudioSessionOptions: const AudioSessionOptions.communication(
      apple: AppleAudioSessionConfiguration(
        category: AppleAudioCategory.playAndRecord,
        categoryOptions: {
          AppleAudioCategoryOption.allowBluetooth,
          AppleAudioCategoryOption.allowBluetoothA2DP,
          AppleAudioCategoryOption.allowAirPlay,
          AppleAudioCategoryOption.defaultToSpeaker,
        },
        mode: AppleAudioMode.spokenAudio,
      ),
      android: AndroidAudioSessionConfiguration(
        audioMode: AndroidAudioMode.inCommunication,
        manageAudioFocus: true,
        focusMode: AndroidAudioFocusMode.gain,
        streamType: AndroidAudioStreamType.music,
        usageType: AndroidAudioAttributesUsageType.media,
        contentType: AndroidAudioAttributesContentType.speech,
        forceAudioRouting: true,
      ),
    ),
  );

  runApp(const RetainMindApp());
}

class RetainMindApp extends StatelessWidget {
  const RetainMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Plus Jakarta Sans Typography Theme (DESIGN.md)
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExamProvider()),
      ],
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppConstants.background,
          textTheme: baseTextTheme,
          colorScheme: const ColorScheme.dark(
            primary: AppConstants.primary,
            onPrimary: AppConstants.onPrimary,
            primaryContainer: AppConstants.primaryContainer,
            surface: AppConstants.surface,
            onSurface: AppConstants.textPrimary,
            error: AppConstants.error,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppConstants.background,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: AppConstants.textPrimary),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
