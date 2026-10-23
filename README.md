# RetainMind (`retain_mind`)

Assistente vocale socratico per esami orali universitari, con client Flutter e backend real-time basato su Pipecat.

---

## 🏛️ Struttura del Progetto

Il progetto unifica il client frontend in Flutter e il backend vocale intelligente:

```text
retain_mind/
├── lib/                              # Frontend Flutter
│   ├── main.dart                     # Entry point Material 3 Dark Academic
│   ├── constants.dart                # Palette, stati FSM e configurazione host
│   ├── models/                       # Modelli dati tipizzati (Session, Plan, Report)
│   ├── services/
│   │   ├── api_service.dart          # Client REST per sessioni, corsi, piani e report
│   │   └── pipecat_service.dart     # Audio PCM su WebSocket verso il backend Pipecat
│   ├── providers/
│   │   └── exam_provider.dart        # State Management centralizzato
│   ├── screens/
│   │   ├── home_screen.dart          # Home con avatar vivente e avvio esame
│   │   ├── exam_screen.dart          # Canvas esame (GrokAvatar, trascrizione live, controlli)
│   │   └── report_screen.dart        # Dashboard BKT, RCA e confronto iterazioni
│   └── widgets/
│       ├── avatar/                   # GrokAvatar (motore SVG/Canvas 3D ispirato a bloub)
│       │   ├── avatar_math.dart      # Proiezione sferica ortografica 3D
│       │   ├── avatar_models.dart    # Pose ed espressioni per gli stati pedagogici
│       │   └── grok_avatar.dart      # Widget CustomPainter animato e reattivo
│       ├── bkt_progress_bar.dart     # Progresso esame e badge FSM
│       └── transcript_bubble.dart    # Turni di conversazione con ΔMastery
│
├── pubspec.yaml                      # Dipendenze Flutter (audio PCM, WebSocket, provider, grafici)
├── android/                          # Configurazione Android (permessi microfono e rete)
├── ios/                              # Configurazione iOS (NSMicrophoneUsageDescription)
├── macos/                            # Configurazione macOS (audio-input & network entitlements)
│
├── docs/                             # Documentazione formale di progetto
│   ├── RetainMind_RAD.md             # Requirements Analysis Document (RAD) completo
│   └── RetainMind_Business_Model_Canvas.md
│
└── backend/                          # Backend FastAPI + Pipecat (Python)
    ├── src/
    │   ├── agent.py                  # Pipeline vocale Pipecat: Gemini Live predefinito, cascaded opzionale
    │   ├── api.py                    # API REST, WebSocket Flutter e signaling SmallWebRTC
    │   ├── assessment/               # Valutazione, BKT, FSM, sessioni e store per corso
    │   ├── rag/                      # Neo4j, Qdrant, Knowledge Graph
    │   ├── planning/                 # Topological Examination Planner
    │   └── config.py                 # Gestione configurazione locale/cloud
    ├── tests/                        # Suite di test pytest completa
    ├── pyproject.toml                # Specifiche dipendenze Python (uv)
    ├── start_agent_cloud.sh          # Alias per l'avvio del server unificato Pipecat
    ├── start_api_server.sh           # Avvia API REST e sessioni vocali (porta 8000)
    └── examination_plan.json         # Piano didattico e grafo dei prerequisiti
```

---

## 🚀 Guida di Avvio Rapido

### 1. Avviare il Backend (da terminale)
```bash
cd backend

# Avvia in un solo terminale: API REST e agent Pipecat
./start_api_server.sh
```

`start_agent_cloud.sh` è mantenuto per compatibilità e richiama lo stesso server: non avviare entrambi gli script contemporaneamente.

La modalità vocale predefinita è Gemini Live (`gemini-3.8-live`, voce `Aoede`). Per usare in alternativa la pipeline cascaded STT → LLM → TTS, impostare `AGENT_PIPELINE_MODE=cascaded` in `backend/.env.local`.

Per creare un piano da un argomento, l'app consente di scegliere livello e durata e mostra una revisione della dispensa e degli argomenti generati prima di avviare l'interrogazione. Il modello predefinito di generazione del piano è `gemini-3.5-flash-lite` (`PLAN_GENERATION_MODEL`).

### 2. Avviare l'Applicazione Flutter (da Android Studio o da terminale)
Dalla radice del progetto:
```bash
flutter pub get

# Per eseguire su macOS Desktop:
flutter run -d macos

# Oppure su iOS Simulator / Android Emulator / Web:
flutter run -d ios
flutter run -d android
flutter run -d chrome
```

---

## 🤖 Caratteristiche dell'Avatar Grok-Bot (`GrokAvatar`)
* **Proiezione Tangente Sferica 3D**: Modellazione matematica derivata da `jeremy-prt/bloub` per proiettare gli occhi a capsula su una sfera tridimensionale con inclinazione naturale asimmetrica.
* **Reattività Dinamica all'Audio & FSM**:
  * **`IDLE`**: Respirazione tranquilla e ammiccamento spontaneo.
  * **`LISTENING`**: Occhi dilatati (+15%), sguardo attento frontale e cenno d'ascolto.
  * **`THINKING`**: Sguardo verso l'alto, occhi socchiusi e satellite luminoso orbitante.
  * **`SPEAKING`**: Risonanza vocale del corpo e occhi espressivi.
  * **Stati Pedagogici**: Espressioni modellate per `SCAFFOLDING`, `CAUSAL_NARROWING` e `CONCEPTUAL_COLLISION`.
* **Valutazione basata sul piano**: le risposte sono confrontate con i punti attesi; gli argomenti con prova applicativa vengono verificati prima di essere segnati come acquisiti.
