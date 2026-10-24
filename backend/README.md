# RetainMind Backend

Backend per esami orali e monitoraggio pedagogico basato su **FastAPI** e **Pipecat**. L'app Flutter usa **SmallWebRTC** come trasporto vocale esclusivo.

Il server FastAPI ospita REST, sessioni Pipecat e signaling WebRTC sulla porta `8000`. La modalità vocale predefinita è **Gemini Live** (`AGENT_PIPELINE_MODE=gemini_live`), con modello `gemini-3.8-live` e voce `Aoede`. La pipeline cascaded STT → LLM → TTS è opzionale e si attiva con `AGENT_PIPELINE_MODE=cascaded`.

### Trasporto audio Flutter

Flutter si collega agli endpoint SmallWebRTC di FastAPI (`POST /api/offer` o `/api/session/webrtc`, con patch ICE su `/api/offer`). Pipecat gestisce la traccia audio WebRTC bidirezionale; il browser/SDK WebRTC si occupa di codec, jitter buffering, acquisizione e riproduzione. Il client richiede echo cancellation, noise suppression e auto gain control.

Su Android la configurazione usa `MODE_NORMAL` (`AndroidAudioMode.normal`) con focus `gain` per un'uscita audio puramente multimediale (`USAGE_MEDIA`, `STREAM_MUSIC`, `CONTENT_TYPE_MUSIC`), con routing forzato (`forceHandleAudioRouting: true`) e sample rate a 48 kHz. Per preservare il microfono senza innescare i filtri telefonici hardware dell'OS, il processamento audio hardware è disabilitato (`androidUseHardwareAudioProcessing: false`), affidando echo cancellation e noise suppression al modulo software WebRTC APM.

La generazione dell'ontologia, del piano e dei materiali da argomento usa `gemini-3.5-flash-lite` come modello predefinito (`PLAN_GENERATION_MODEL`). È indipendente dal modello vocale Gemini Live (`GEMINI_LIVE_MODEL`), predefinito a `gemini-3.8-live` con voce `Aoede`. La pipeline vocale `cascaded` è opzionale; i provider effettivi dipendono dalle chiavi e dal codice/configurazione del ramo selezionato.

I piani creati da un argomento accettano livello (`base`, `intermedio`, `avanzato`) e durata (10–60 minuti). La risposta API include la dispensa e gli argomenti generati, che Flutter presenta per revisione prima di avviare l'esame. I materiali caricati restano preferibili quando occorre aderire a un programma didattico specifico.

### Comportamento dell'esaminatore

Le istruzioni comuni sono definite in `src/prompts/examiner.py`; titolo del corso, programma e saluto iniziale vengono aggiunti da `build_examiner_system_instructions`. La gestione del turno distingue risposte, chiarimenti pertinenti, digressioni fuori tema e comandi di controllo:

- Le risposte d'esame passano al valutatore basato su rubriche e riferimenti del corso. Il minimo è di tre tentativi per argomento, anche per i piani salvati con un valore inferiore.
- Un chiarimento riconosciuto come pertinente riceve una risposta breve dal contesto verificato; non aggiorna BKT, tentativi o piano. In modalità Gemini/LLM l'agente formula la risposta; il fallback locale usa l'ideal answer o il sommario disponibile.
- Una digressione chiaramente estranea viene reindirizzata alla domanda corrente e registrata come `STUDENT_TURN_ROUTED`; non viene valutata e non consuma un tentativo.
- Pausa e ripresa sono controlli espliciti. Durante la pausa l'agente non valuta né dà suggerimenti e riparte solo dopo una richiesta chiara.

Il rilevamento di chiarimenti e digressioni usa corrispondenze lessicali/stem con la domanda e il materiale recuperato: è un filtro prudente di instradamento, non un classificatore semantico né un voto. Gli eventi di instradamento conservano la frase originale per la revisione dei falsi positivi.

### Protocollo e strumenti dell'agente vocale (Gemini 3.8 Live & Pipecat)

L'agente espone gli strumenti al modello vocale tramite `FunctionSchema` con risposte conformi al protocollo strutturato (`status: ok`, `retryable: false`):

1. **`evaluate_and_advance(student_response: str)`**: Valuta la risposta sostanziale dello studente aggiornando BKT e FSM pedagogica. Instrada le digressioni fuori tema (`SESSION_OFF_TOPIC_REDIRECT`) senza penalità né consumo di tentativi.
2. **`pause_session()`**: Mette in pausa l'esame su richiesta esplicita dello studente e persiste lo stato su disco.
3. **`resume_session()`**: Riprende la sessione precedentemente sospesa da dove era stata interrotta.
4. **`repeat_examination()`**: Riavvia l'esame dal principio per consentire una nuova iterazione e il confronto diagnostico dei progressi.
5. **`get_exam_progress()`**: Restituisce il punteggio medio BKT, lo stato di padronanza dei concetti e i dettagli del piano.
6. **`get_exam_history_and_comparison()`**: Fornisce un confronto diagnostico cross-iterazione tra il tentativo attuale e quelli precedenti.
7. **`get_session_summary()`**: Genera il riepilogo finale diagnostico e di Root-Cause Analysis (RCA) al termine dell'esame.

**Regole di conversazione e guardrail vocali:**
- Massimo 2 chiamate a strumenti consecutive senza parlato all'utente.
- Pronuncia immediata della direttiva pedagogica restituita dallo strumento.
- Nessun uso di markdown, elenchi puntati o sintassi codice nel parlato generato (testo piano per sintesi vocale).
- Politica anti-ripetizione: divieto di riproporre la stessa identica formulazione due volte consecutive.

---

## 🏛️ Architettura dei Componenti

Il backend è strutturato in moduli indipendenti e cooperanti secondo principi di separazione delle responsabilità:

```text
backend/
├── src/
│   ├── agent.py                  # Pipeline vocale Pipecat (Gemini Live predefinito; cascade opzionale)
│   ├── api.py                    # Server unificato FastAPI (REST e SmallWebRTC)
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
