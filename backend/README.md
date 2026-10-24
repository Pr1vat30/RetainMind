# RetainMind Backend

Backend per esami orali e monitoraggio pedagogico basato su **FastAPI** e **Pipecat**. L'app Flutter usa **SmallWebRTC** per l'audio per impostazione predefinita; il trasporto **WebSocket PCM** resta disponibile come fallback.

Il server FastAPI ospita REST, sessioni Pipecat e trasporti audio sulla porta `8000`. La modalità vocale predefinita è **Gemini Live** (`AGENT_PIPELINE_MODE=gemini_live`), con modello `gemini-3.8-live` e voce `Aoede`. La pipeline cascaded STT → LLM → TTS è opzionale e si attiva con `AGENT_PIPELINE_MODE=cascaded`.

### Trasporto audio Flutter

Flutter si collega per default agli endpoint SmallWebRTC di FastAPI (`POST /api/offer` o `/api/session/webrtc`, con patch ICE su `/api/offer`). Pipecat gestisce la traccia audio WebRTC bidirezionale; il browser/SDK WebRTC si occupa di codec, jitter buffering, acquisizione e riproduzione. Il client chiede echo cancellation, noise suppression e auto gain control.

Su Android la configurazione provata usa `MODE_IN_COMMUNICATION` per mantenere acquisizione microfono e routing full-duplex; imposta gli `AudioAttributes` di uscita su `USAGE_MEDIA` e `CONTENT_TYPE_MUSIC`, disabilita l'audio processing hardware WebRTC e richiede 48 kHz. Quindi l'uscita è classificata come media, ma il microfono resta gestito da WebRTC in modalità di comunicazione.

Per tornare al protocollo PCM si compila Flutter con `--dart-define=USE_WEBRTC_AUDIO=false`.

#### Fallback WebSocket PCM

Il client si collega a `/ws/{course_id}` (o `/ws` per il corso attivo) e invia PCM signed 16-bit little-endian, mono, a 16 kHz. Gemini Live restituisce PCM mono a 24 kHz. Ogni messaggio audio è JSON con payload Base64:

```json
{
  "event": "audio",
  "audio": {
    "encoding": "pcm_s16le",
    "sampleRate": 16000,
    "channels": 1,
    "payload": "..."
  }
}
```

Il server usa la stessa struttura in uscita con `sampleRate: 24000`. L'evento `clear` interrompe e svuota l'audio accodato durante un'interruzione dell'assistente. La serializzazione è gestita da `src/pcm_serializer.py`; evitare conversioni μ-law o ricampionamenti aggiuntivi nel client.

La generazione dell'ontologia, del piano e dei materiali da argomento usa `gemini-3.5-flash-lite` come modello predefinito (`PLAN_GENERATION_MODEL`). È indipendente dal modello vocale Gemini Live (`GEMINI_LIVE_MODEL`), predefinito a `gemini-3.8-live` con voce `Aoede`. La pipeline vocale `cascaded` è opzionale; i provider effettivi dipendono dalle chiavi e dal codice/configurazione del ramo selezionato.

I piani creati da un argomento accettano livello (`base`, `intermedio`, `avanzato`) e durata (10–60 minuti). La risposta API include la dispensa e gli argomenti generati, che Flutter presenta per revisione prima di avviare l'esame. I materiali caricati restano preferibili quando occorre aderire a un programma didattico specifico.

### Comportamento dell'esaminatore

Le istruzioni comuni sono definite in `src/prompts/examiner.py`; titolo del corso, programma e saluto iniziale vengono aggiunti da `build_examiner_system_instructions`. La gestione del turno distingue risposte, chiarimenti pertinenti, digressioni fuori tema e comandi di controllo:

- Le risposte d'esame passano al valutatore basato su rubriche e riferimenti del corso. Il minimo è di tre tentativi per argomento, anche per i piani salvati con un valore inferiore.
- Un chiarimento riconosciuto come pertinente riceve una risposta breve dal contesto verificato; non aggiorna BKT, tentativi o piano. In modalità Gemini/LLM l'agente formula la risposta; il fallback locale usa l'ideal answer o il sommario disponibile.
- Una digressione chiaramente estranea viene reindirizzata alla domanda corrente e registrata come `STUDENT_TURN_ROUTED`; non viene valutata e non consuma un tentativo.
- Pausa e ripresa sono controlli espliciti. Durante la pausa l'agente non valuta né dà suggerimenti e riparte solo dopo una richiesta chiara.

Il rilevamento di chiarimenti e digressioni usa corrispondenze lessicali/stem con la domanda e il materiale recuperato: è un filtro prudente di instradamento, non un classificatore semantico né un voto. Gli eventi di instradamento conservano la frase originale per la revisione dei falsi positivi.

---

## 🏛️ Architettura dei Componenti

Il backend è strutturato in moduli indipendenti e cooperanti secondo principi di separazione delle responsabilità:

```text
backend/
├── src/
│   ├── agent.py                  # Pipeline vocale Pipecat (Gemini Live predefinito; cascade opzionale)
│   ├── api.py                    # Server unificato FastAPI (REST, SmallWebRTC e WebSocket /ws)
│   ├── config.py                 # Gestione centralizzata della configurazione e variabili d'ambiente
│   ├── ingest.py                 # Script di ingestione materiali accademici (PDF/MD/TXT -> Graph + Vector)
│   ├── session_cli.py            # CLI da terminale per ispezione stato esame, pause, resume e report
│   │
│   ├── assessment/               # Motore Pedagogico & Valutazione
│   │   ├── bkt.py                # Bayesian Knowledge Tracing (stima probabilistica padronanza P(L))
│   │   ├── fsm.py                # Pedagogical FSM (Exploration, Scaffolding, Narrowing, Collision)
│   │   ├── evaluator.py          # Valutatore delle risposte dello studente e calcolo del ΔMastery
│   │   ├── report.py             # Generazione report diagnostico finale e Root-Cause Analysis (RCA)
│   │   ├── state.py              # SessionAssessmentManager: ciclo di vita sessione, storico e thread-safety
│   │   └── service.py            # SessionService: interfaccia unificata per API e CLI
│   │   └── knowledge.py          # Store condivisi per corso e ripristino dal materiale salvato
│   │
│   ├── planning/                 # Pianificatore Topologico dell'Esame
│   │   ├── models.py             # Schemi Pydantic per concetti, prerequisiti e piano d'esame
│   │   └── planner.py            # Ordinamento topologico dei concetti basato su grafi di dipendenza
│   │
│   ├── rag/                      # RAG Ibrido (Grafo della Conoscenza + Spazio Vettoriale)
│   │   ├── embeddings.py         # Provider per embedding densi
│   │   ├── graph_store.py        # Store del Grafo Ontologico (Neo4j / In-Memory)
│   │   ├── vector_store.py       # Store Vettoriale (Qdrant / In-Memory)
│   │   ├── hybrid_retriever.py   # Recupero combinato semantico + relazioni ontologiche
│   │   └── ingestion/            # Pipeline di estrazione, chunking e parsing documenti
│   │
│   ├── orchestrator/             # Orchestrazione generazione piani e servizi LLM Pipecat
│   │   ├── gemini_orchestrator.py # Integrazione avanzata con Google Gemini
│   │   └── local_llm.py          # FrameProcessor custom per Pipecat in esecuzioni locali
│   │
│   ├── prompts/                  # Direttive e Prompt Pedagogici
│   │   ├── examiner.py           # Direttive per l'Esaminatore Socratico
│   │   └── evaluator.py          # Prompt per la valutazione semantica della padronanza
│   │
│   └── utils/                    # Strumenti di supporto e logging delle chiamate API
│       └── api_interceptor.py
│
├── tests/                        # Suite di test unitari e di integrazione pytest
├── pyproject.toml                # Specifiche del progetto Python e dipendenze (uv)
├── start_api_server.sh           # Avvio Server unificato FastAPI (porta 8000)
└── start_agent_cloud.sh          # Shortcut avvio server Pipecat
```

---

## 🚀 Script di Avvio

1. **Avviare il server unificato FastAPI e Pipecat** (API REST e sessioni vocali):
   ```bash
   ./start_api_server.sh
   ```

2. **In alternativa**, per compatibilità con i comandi precedenti:
   ```bash
   ./start_agent_cloud.sh
   ```

Gli script `start_api_server.sh` e `start_agent_cloud.sh` avviano entrambi il server unificato FastAPI/Pipecat sulla porta `8000`: eseguirne uno solo. Il secondo nome è mantenuto per compatibilità con i comandi precedenti.

Configurare le chiavi necessarie alla modalità scelta in `backend/.env` o `backend/.env.local` (quest'ultimo ha precedenza). Per la modalità predefinita servono `GOOGLE_API_KEY` per generazione e Gemini Live. `DEEPGRAM_API_KEY` e `ELEVEN_API_KEY` servono solo se si attiva la pipeline cascaded. Il client Flutter deve puntare all'indirizzo raggiungibile del server, non a `localhost` quando gira su un dispositivo fisico.

Le istanze graph/vector in memoria sono condivise fra generazione del piano e sessione per corso nel processo corrente. Dopo un riavvio vengono ricostruite dai materiali e dal piano salvati. Neo4j e Qdrant sono disponibili come backend configurabili; in assenza dei relativi servizi il codice ripiega sugli store in memoria.

3. **Eseguire i test**:
   ```bash
   uv run pytest
   ```
