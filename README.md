# RetainMind (`retain_mind`)

Assistente Vocale Socratico AI per Esami Orali Universitari — Sistema Completo Frontend Flutter + Backend LiveKit Agents.

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
│   │   ├── api_service.dart          # Client REST (Token, Stato BKT, Trascrizioni, Report)
│   │   └── livekit_service.dart      # WebRTC Room & Microfono LiveKit
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
├── pubspec.yaml                      # Dipendenze Flutter (livekit_client, provider, fl_chart, ecc.)
├── android/                          # Configurazione Android (permessi microfono e rete)
├── ios/                              # Configurazione iOS (NSMicrophoneUsageDescription)
├── macos/                            # Configurazione macOS (audio-input & network entitlements)
│
├── docs/                             # Documentazione formale di progetto
│   ├── RetainMind_RAD.md             # Requirements Analysis Document (RAD) completo
│   └── RetainMind_Business_Model_Canvas.md
│
└── backend/                          # Backend LiveKit Voice Agent (Python)
    ├── src/
    │   ├── agent.py                  # LiveKit Voice Agent (Gemini Live / Cascade)
    │   ├── api.py                    # Server REST & Token Gateway (FastAPI/aiohttp)
    │   ├── assessment/               # BKT, Pedagogical FSM, RCA Report, SessionService
    │   ├── rag/                      # Neo4j, Qdrant, Knowledge Graph
    │   ├── planning/                 # Topological Examination Planner
    │   └── config.py                 # Gestione configurazione locale/cloud
    ├── tests/                        # Suite di test pytest completa
    ├── pyproject.toml                # Specifiche dipendenze Python (uv)
    ├── start_agent_cloud.sh          # Avvia Voice Agent collegato a LiveKit Cloud
    ├── start_api_server.sh           # Avvia Server REST & Token API (porta 8000)
    └── examination_plan.json         # Piano didattico e grafo dei prerequisiti
```

---

## 🚀 Guida di Avvio Rapido

### 1. Avviare il Backend (da terminale)
```bash
cd backend

# Terminale 1: Server REST & Token API per Flutter
./start_api_server.sh

# Terminale 2: Voice Agent LiveKit Cloud
./start_agent_cloud.sh
```

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
