package com.example.retain_mind

import android.media.AudioManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // WebRTC su Android viene instradato tramite lo stream delle comunicazioni vocali (STREAM_VOICE_CALL).
        // Vincoliamo i tasti fisici del volume a STREAM_VOICE_CALL per controllare direttamente la voce dell'esaminatore.
        volumeControlStream = AudioManager.STREAM_VOICE_CALL
    }
}

