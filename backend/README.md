# RetainMind Backend

Backend vocale intelligente basato su **LiveKit Agents** e **Gemini Live** per la conduzione autonoma di esami orali universitari e monitoraggio pedagogico continuo.

---

## 🏛️ Architettura dei Componenti

Il backend è strutturato in moduli indipendenti e cooperanti secondo principi di separazione delle responsabilità:

```text
backend/
├── src/
│   ├── agent.py                  # LiveKit Voice Agent: punto di ingresso per sessioni vocali full-duplex
│   ├── api.py                    # Server REST aiohttp/FastAPI per generazione Token JWT e telemetria
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
│   │
│   ├── planning/                 # Pianificatore Topologico dell'Esame
│   │   ├── models.py             # Schemi Pydantic per concetti, prerequisiti e piano d'esame
│   │   └── planner.py            # Ordinamento topologico dei concetti basato su grafi di dipendenza
│   │
│   ├── rag/                      # RAG Ibrido (Grafo della Conoscenza + Spazio Vettoriale)
│   │   ├── embeddings.py         # Provider per embedding densi
│   │   ├── graph_store.py        # Store del Grafo Ontologico (Neo4j / In-Memory NetworkX)
│   │   ├── vector_store.py       # Store Vettoriale (Qdrant / In-Memory)
│   │   ├── hybrid_retriever.py   # Recupero combinato semantico + relazioni ontologiche
│   │   └── ingestion/            # Pipeline di estrazione, chunking e parsing documenti
│   │
│   ├── orchestrator/             # Orchestrazione LLM & Streaming
│   │   ├── gemini_orchestrator.py # Integrazione avanzata con Google Gemini
│   │   └── local_llm.py          # Provider custom LLM per test locali
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
├── Dockerfile                    # Container Docker multi-stage per deployment su LiveKit Cloud
├── examination_plan.json         # Piano didattico precaricato di riferimento
├── .env.example                  # Template delle variabili d'ambiente
├── start_agent_cloud.sh          # Avvio Voice Agent su LiveKit Cloud
└── start_api_server.sh           # Avvio Server REST & Token Gateway (porta 8000)
```

---

## 🚀 Script di Avvio

1. **Avviare il server REST / Token API** (necessario per l'app mobile/desktop Flutter):
   ```bash
   ./start_api_server.sh
   ```

2. **Avviare il Voice Agent (LiveKit Cloud)**:
   ```bash
   ./start_agent_cloud.sh
   ```

3. **Eseguire i test**:
   ```bash
   uv run pytest
   ```
