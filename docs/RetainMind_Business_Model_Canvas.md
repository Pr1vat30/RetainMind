# Business Model Canvas — RetainMind
**Progetto:** RetainMind — Autonomous Socratic Oral Examiner  
**Documento di riferimento:** `RetainMind_RAD.md` (RM-RAD-2026-V2.0)  
**Framework:** The 9 Building Blocks of the Business Model Canvas (Alexander Osterwalder & Yves Pigneur)  

---

## 📌 Struttura del Documento
Il presente documento è articolato in due parti:
1. **Parte 1 — Sintesi Incisiva (Canvas Ready):** Formulazioni concise, dense e strutturate a punti (bullet points), pronte per essere inserite direttamente nei 9 riquadri grafici del template del Business Model Canvas.
2. **Parte 2 — Approfondimento Strategico e Dettagliato:** Analisi estesa di ciascuno dei 9 blocchi, con focus sul contesto accademico, l'architettura tecnologica (Pipecat, FastAPI, GraphRAG, BKT), le dinamiche economiche e la strategia di scalabilità.

---

# PARTE 1: Sintesi Incisiva (Canvas Ready)

```
┌─────────────────────────┬─────────────────────────┬─────────────────────────┬─────────────────────────┬─────────────────────────┐
│ 8. KEY PARTNERS         │ 7. KEY ACTIVITIES       │ 1. VALUE PROPOSITIONS   │ 4. CUSTOMER RELATIONS   │ 2. CUSTOMER SEGMENTS    │
│                         │                         │                         │                         │                         │
│ • Pipecat & API       │ • R&D Audio Voice AI    │ • Simulazione orale     │ • Voice-driven UX       │ • Studenti Universitari │
│   Infrastructure        │   e S2S a bassa latenza │   realistica a voce     │   empatica e socratica  │   facoltà complesse     │
│ • Provider Modelli AI   │ • Ottimizzazione motore │   (full-duplex, fluida) │ • Onboarding guidato    │   (Medicina, Legge,     │
│   (Google Cloud Gemini) │   pedagogico BKT & FSM  │ • Feedback diagnostico  │   totalmente vocale     │   Ingegneria, STEM)     │
│ • Database Vendors      │ • Sviluppo GraphRAG     │   immediato e guidato   │ • Dashboard trasparente │ • Candidati a Concorsi  │
│   (Neo4j, Qdrant)       │   (Neo4j + Qdrant)      │   (Scaffolding puntuale)│   sui progressi (BKT)   │   Pubblici & Abilitaz.  │
│ • Docenti e Università  │ • Ingestion affidabile  │ • Root Cause Analysis   │ • Autonomia self-service│ • Istituti Accademici & │
│   (Partner didattici)   │   di documenti complessi│   sulle lacune pregresse│   h24 senza giudizio    │   Atenei (B2B didattica)│
│ • Associazioni e        │ • Manutenzione WebRTC   │ • Abbattimento ansia da │ • Community accademica  │ • Centri di Formazione  │
│   Rappresentanti        │   e infrastruttura RTC  │   esame e allenamento   │   e peer support        │   e Master Specialistici│
│   Studenteschi          │                         │   all'argomentazione    │                         │                         │
├─────────────────────────┼─────────────────────────┤ • Studio personalizzato ├─────────────────────────┼─────────────────────────┤
│ 6. KEY RESOURCES        │                         │   sui propri materiali  │ 3. CHANNELS             │                         │
│                         │                         │   (PDF, slide, appunti) │                         │                         │
│ • Pipeline Pipecat │                         │                         │ • Web Application       │                         │
│   Pipecat WebSocket PCM │                         │                         │   e Mobile Voice Room   │                         │
│ • Modello BKT & FSM     │                         │                         │ • Passaparola virale &  │                         │
│   di valutazione vocale │                         │                         │   community studentesche│                         │
│ • Motore GraphRAG       │                         │                         │ • Social Education      │                         │
│   (Ontologie + Vettori) │                         │                         │   (TikTok, IG, YouTube) │                         │
│ • Know-how ingegneristico                         │ • Accordi con atenei &  │                         │                         │
│   AI & Scienza Didattica│                         │   dipartimenti (B2B)    │                         │                         │
│ • Dati diagnostici anon.│                         │ • CLI per sviluppatori  │                         │                         │
├─────────────────────────┴─────────────────────────┴─────────────────────────┴─────────────────────────┴─────────────────────────┤
│ 9. COST STRUCTURE                                                           │ 5. REVENUE STREAMS                                │
│                                                                             │                                                   │
│ • Costi AI: generazione piani e provider vocali                             │ • Abbonamento B2C Freemium / Tier Pro (Mensile/Annuale)          │
│ • Hosting API e traffico WebSocket/WebRTC                                   │ • Pacchetti "Crediti Esame" Pay-per-Use per sessioni intensive    │
│ • Gestione cluster Database (Neo4j Graph Database, Qdrant Vector Store)     │ • Licenze Istituzionali SaaS B2B per Università e Dipartimenti    │
│ • Costi di sviluppo, testing, manutenzione ed engineering software          │ • Piani Enterprise per Accademie Private e Scuole Forensi/Mediche│
│ • Customer acquisition (Marketing accademico, partnership, community)      │                                                   │
└─────────────────────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────┘
```

### 1. Value Propositions (Proposte di Valore)
* **Simulazione Orale Realistica e Continua:** Sessioni vocali real-time basate su Pipecat, con latenza e qualità da misurare sui dispositivi e provider configurati.
* **Valutazione Socratica e Scaffolding:** La valutazione confronta le risposte trascritte con i punti attesi nel piano; il sistema può guidare lo studente con domande mirate.
* **Root Cause Analysis (RCA) delle Lacune:** Identificazione algoritmica dei concetti propedeutici non compresi che causano errori su argomenti complessi, grazie all'ontologia a grafo.
* **Tracciamento delle Competenze:** Stima della padronanza tramite BKT, da interpretare come indicatore pedagogico.
* **Superamento dell'Ansia da Esame:** Ambiente di simulazione privato, sicuro, non giudicante e disponibile h24 per acquisire scioltezza verbale e capacità di sintesi.
* **Grounding su Materiali Propri:** Piano e recupero possono usare i materiali caricati; il grounding riduce ma non elimina il rischio di errori.

### 2. Customer Segments (Segmenti di Clientela)
* **Studenti Universitari (Discipline ad Alto Rigore Concettuale):** Iscritti a facoltà con esami orali determinanti (Medicina e Chirurgia, Giurisprudenza, Ingegneria, Economia, Fisica, Informatica).
* **Candidati a Concorsi Pubblici ed Esami di Stato:** Aspiranti magistrati, avvocati, medici specializzandi, notai, docenti in preparazione alla prova orale.
* **Atenei e Dipartimenti Universitari (B2B):** Università interessate a ridurre i tassi di abbandono (drop-out), supportare gli studenti in debito d'esame e monitorare l'efficacia didattica.
* **Accademie di Formazione e Business School Private:** Istituti che desiderano offrire un tutor vocale proprietario personalizzato per i propri iscritti.

### 3. Channels (Canali)
* **Canali di Fruizione (Delivery):** Client Flutter con audio WebSocket PCM; WebRTC tramite signaling SmallWebRTC dove configurato e CLI per power users/sviluppatori.
* **Canali di Acquisizione B2C:** 
  * Passaparola virale tra studenti e gruppi corso (Telegram, WhatsApp, Discord accademici).
  * Content marketing "Study-with-me" e dimostrazioni audio su TikTok, Instagram Reels, YouTube Edu.
  * Collaborazioni con associazioni universitarie e rappresentanti degli studenti.
* **Canali di Vendita B2B:** Vendita diretta enterprise a rettorati, presidenti di corso di laurea e responsabili e-learning/EdTech.

### 4. Customer Relationships (Relazioni con i Clienti)
* **Interazione Conversazionale Vocale Umanizzata:** Persona AI accademica, autorevole ma costruttiva ed empatica, focalizzata sulla maieutica socratica.
* **Self-Service & Zero Barriere:** Caricamento drag-and-drop dei documenti e avvio immediato della sessione vocale senza configurazioni complesse.
* **Fiducia e Trasparenza Pedagogica:** Visualizzazione chiara dei progressi, delle aree deboli individuate dal BKT e possibilità di consultare/esportare l'intera trascrizione dell'esame.
* **Privacy-First & No Judgment Zone:** Libertà psicologica per lo studente di ammettere lacune e sbagliare senza alcun timore di giudizio accademico o sociale.

### 5. Revenue Streams (Flussi di Ricavi)
* **B2C — Abbonamento Freemium (Tier Pro):** Canone mensile (es. 14,99 €/mese) o stagionale/sessione d'esami (es. 39,99 €/trimestre) per simulazioni orali illimitate, caricamento illimitato di PDF e report RCA completi.
* **B2C — Pacchetti Pay-per-Use ("Crediti Esame"):** Microtransazioni (es. 9,99 € per pacchetto da 5 esami completi) per chi necessita di preparare una singola sessione specifica.
* **B2B — Licenze Istituzionali SaaS per Atenei:** Prezzo a licenza/studente/anno per l'adozione su interi corsi di laurea, integrata con dashboard analitica aggregata per i docenti.
* **B2B — Piani Custom per Scuole Forensi & Post-Laurea:** Setup fee per ontologie personalizzate di facoltà + abbonamento enterprise con SLA dedicato.

### 6. Key Resources (Risorse Chiave)
* **Architettura Tecnologica Vocale:** Pipeline vocale real-time basata su Pipecat, con WebSocket PCM per Flutter e modalità cascaded predefinita; Gemini Live è opzionale. La generazione dei piani usa `gemini-3.5-flash-lite` come default.
* **Algoritmi e Modelli Proprietari:** Motore pedagogico FSM, implementazione del Bayesian Knowledge Tracing (BKT) e logica di Root Cause Analysis (RCA).
* **Infrastruttura Dati Hybrid GraphRAG:** Grafo della conoscenza ontologico (Neo4j) e database vettoriale (Qdrant) per l'indicizzazione concettuale topologica.
* **Modelli Fondazionali di Linguaggio e Voce:** Accesso a modelli per pipeline cascaded (STT, LLM, TTS) e modalità Gemini Live opzionale.
* **Team Multidisciplinare:** Competenze integrate in AI Engineering, audio streaming e WebSocket/WebRTC, Data Engineering e Cognitive Learning Science.

### 7. Key Activities (Attività Chiave)
* **Ottimizzazione Continua della Latenza Vocale:** Ottimizzazione dei buffer audio e del trasporto WebSocket/WebRTC per preservare una risposta naturale e fluida sub-secondo.
* **Evoluzione della Logica Pedagogica:** Perfezionamento del rilevamento di esitazioni vocali (`filler words`, pause) e affinamento delle strategie di scaffolding.
* **Ingegnerizzazione dell'Ingestion Documentale:** Miglioramento dell'estrazione dai formati supportati; OCR per materiali scansionati è un'evoluzione da valutare.
* **Manutenzione e Scalabilità dell'Infrastruttura:** Gestione del server FastAPI/Pipecat e degli eventuali servizi Neo4j e Qdrant.
* **Community Building e Marketing Accademico:** Presidio delle comunità universitarie, raccolta feedback dagli studenti e validazione sul campo dei tassi di superamento esami.

### 8. Key Partners (Partner Chiave)
* **Cloud & Infrastructure Providers:** Google (generazione piani e Gemini Live opzionale), provider STT/LLM/TTS e hosting FastAPI.
* **Database Vendors:** Neo4j (graph database) e Qdrant (vector engine specializzato).
* **Ecosistema Accademico:** Docenti innovatori, tutor universitari, comitati di corso di studio e associazioni studentesche.
* **Case Editrici e Piattaforme di Appunti:** Potenziali collaborazioni con editori universitari (es. Maggioli, Cedam, Pearson) o piattaforme di sharing appunti per l'ingestion legale di testi d'esame.

### 9. Cost Structure (Struttura dei Costi)
* **Costi di Inferenza AI (Variabili):** Dipendono dai modelli configurati per piani e voce; embedding e OCR comportano costi solo se attivati.
* **Infrastruttura Server e Rete (Fissi/Semi-variabili):** Hosting API, traffico audio, inferenza dei provider e servizi Neo4j/Qdrant quando attivati.
* **Sviluppo Software e Ricerca (Fissi):** Retribuzioni del team di ingegneria AI, sviluppatori full-stack, DevOps e specialisti di scienze dell'apprendimento.
* **Costi di Marketing e Vendita (Variabili):** Campagne di acquisizione digitale nei periodi di sessione esami, sponsorship di eventi universitari e attività promozionali.
* **Conformità e Amministrazione:** Spese di compliance GDPR, protezione dei dati biometrici/vocali degli studenti, consulenza legale e sicurezza dei dati.

---

# PARTE 2: Approfondimento Strategico e Dettagliato

---

### 1. Value Propositions (Proposte di Valore)

La proposta di valore di RetainMind si posiziona in una breccia critica del mercato dell'istruzione superiore: **il divario tra lo studio passivo e la prova d'esame orale**.

#### Il Problema di Fondo
Nelle università europee e segnatamente in quelle italiane, l'esame orale rappresenta spesso lo scoglio più arduo e selettivo. Mentre per i test scritti a risposta multipla esistono strumenti affermati (come Anki, Quizlet o SuperMemo basati su flashcard atomiche), **non esiste alcuno strumento capace di preparare lo studente alla verbalizzazione dialettica e all'articolazione logico-causale di concetti complessi**. 
Gli studenti soffrono di:
* **Illusion of Competence (Illusione di Sapere):** Credono di padroneggiare un argomento leggendo e sottolineando, ma si bloccano quando devono argomentarlo a parole.
* **Ansia da Prestazione e Blocco Emotivo:** Paura del giudizio del docente, incapacità di gestire il silenzio e la pressione dell'interrogazione frontale.
* **Costi Elevati delle Ripetizioni Private:** Le lezioni individuali con tutor umani costano tra i 25€ e i 60€ all'ora, risultando insostenibili per la maggior parte degli studenti universitari.

#### La Soluzione Differenziante di RetainMind
1. **Interrogazione Socratico-Maieutica in Tempo Reale:** A differenza dei comuni assistenti vocali che fungono da risponditori passivi o enciclopedie parlanti, RetainMind assume il ruolo del **docente esaminatore**. Pone la domanda, ascolta attentamente, non interrompe bruscamente e reagisce con risposte vocali immediate.
2. **Follow-up guidati dal piano:** Il valutatore confronta la risposta trascritta con i punti chiave attesi. Il piano può fornire domande successive per approfondire le lacune emerse.
3. **Root Cause Analysis (RCA) tramite Ontologia a Grafo:** Se uno studente fallisce l'interrogazione su un concetto avanzato (es. *Teorema CAP* o *Sharding*), il sistema non si limita a registrarlo come fallimento: risale l'ontologia delle dipendenze (`REQUIRES`) per verificare se la lacuna risieda in una mancata comprensione delle basi propedeutiche (es. *Modello Relazionale* o *Consistenza Dati*).
4. **Tracciamento Matematico tramite Bayesian Knowledge Tracing (BKT):** La conoscenza non è trattata come una percentuale statica, ma come una distribuzione probabilistica $P(L_t)$. Il sistema modella matematicamente la probabilità di apprendimento ($P(T)$), di errore casuale/scivolone ($P(S)$) e di intuizione corretta ($P(G)$), consentendo un quadro scientifico della preparazione.
5. **Session Management Continuo e Flessibile:** Supporto nativo per la pausa vocale spontanea (*"Mettiamo in pausa"*), ripresa successiva senza perdita di contesto, e iterazioni ripetute con ricalibrazione automatica sui punti deboli emersi nelle sessioni precedenti.

---

### 2. Customer Segments (Segmenti di Clientela)

Il modello individua un approccio ibrido **B2C (Student-First)** e **B2B / B2B2C (Institutional)**.

#### A. Segmento B2C Primario: Studenti Universitari di Facoltà Intensive
* **Medicina e Chirurgia / Professioni Sanitarie:** Esami mastodontici (Anatomia Umana, Farmacologia, Patologia Generale) caratterizzati da migliaia di dettagli ontologici, relazioni causali fisiopatologiche e tradizionali orali lunghi e selettivi.
* **Giurisprudenza:** Diritto Privato, Penale, Costituzionale. Lo studente deve dimostrare non solo memoria mnemonica delle norme, ma proprietà di linguaggio tecnico-giuridico, capacità ermeneutica e coordinamento tra istituti giuridici.
* **Ingegneria & Computer Science:** Corsi avanzati (Basi di Dati, Reti di Calcolatori, Sistemi Operativi, Algoritmi) dove le dimostrazioni orali, i trade-off architetturali e i principi teorici sono verificati oralmente.
* **Scienze Dure (Fisica, Matematica, Chimica):** Necessità di spiegare oralmente dimostrazioni, principi di conservazione, teoremi e modelli fenomenologici.

#### B. Segmento B2C Secondario: Post-Graduate & Concorsi Pubblici
* Candidati all'Esame di Stato per l'Abilitazione Forense o all'Esame da Magistrato.
* Medici in preparazione per il Concorso Nazionale SSM (Scuole di Specializzazione Medica).
* Partecipanti a concorsi pubblici selettivi con prova orale vincolante (Diplomazia, Agenzia delle Entrate, Pubblica Amministrazione).

#### C. Segmento B2B: Atenei e Dipartimenti Universitari
* **Fattori di spinta (Pains):** Elevati tassi di abbandono al primo/secondo anno (drop-out), sovraffollamento dei corsi, studenti "fuori corso" bloccati su singoli esami-scoglio (es. Diritto Privato o Chimica Generale).
* **Opportunità (Gains):** Fornire uno strumento di tutorato continuo h24 a costo scalabile per ateneo, riducendo il sovraccarico orario dei docenti e dei ricercatori durante i ricevimenti e offrendo un pre-screening oggettivo dello stato di coorte.

#### D. Segmento B2B Specializzato: Accademie di Preparazione Privata
* Scuole di preparazione ai test universitari o alle carriere legali/notarili, desiderose di integrare nella propria offerta un "simulatore vocale di commissione d'esame" white-label.

---

### 3. Channels (Canali)

I canali riflettono la doppia natura dell'iniziativa, orchestrando l'esperienza utente e la penetrazione commerciale.

#### Canali di Erogazione e Fruizione (Delivery Channels)
* **Client vocale Flutter:** invia e riceve audio PCM via WebSocket e visualizza trascrizione e stato audio. SmallWebRTC signaling è disponibile per client WebRTC compatibili.
* **Progressive Web App (PWA) / Mobile App:** Ottimizzata per l'uso in mobilità (ad es. ripasso orale all'aperto o in cuffia camminando).
* **CLI (Command Line Interface - `session_cli.py`):** Un canale potente per power user, ricercatori e studenti informatici che preferiscono operare da terminale con esportazioni immediate in Markdown dei propri appunti d'esame.

#### Canali di Comunicazione e Acquisizione B2C
* **Peer-to-Peer & Viral Loop Universitario:** L'adozione nelle facoltà avviene a macchia d'olio: quando uno studente supera brillantemente un esame notoriamente proibitivo grazie a RetainMind, la notizia si diffonde rapidamente nei gruppi Telegram/WhatsApp del corso.
* **Social Proof & Short-Form Video Content:** Campagne video su TikTok e Instagram incentrate su:
  * *"Ho fatto interrogare l'AI su Anatomia: ecco come ha distrutto le mie incertezze"*.
  * Simulazioni d'esame realistiche con audio e barge-in dimostrativi.
* **Ambassador di Facoltà:** Partnership con studenti autorevoli, rappresentanti degli studenti e community universitarie digitali.

#### Canali Commerciali B2B
* **Vendita Diretta Istituzionale:** Incontri e pilot dimostrativi con Prorettori alla Didattica, Delegati all'Innovazione Digitale e Direttori di Dipartimento.
* **Conferenze Didattiche ed EdTech:** Partecipazione a conferenze sull'e-learning, innovazione universitaria e intelligenza artificiale per l'educazione.

---

### 4. Customer Relationships (Relazioni con i Clienti)

La relazione che RetainMind stabilisce con l'utente è intimamente legata all'esperienza psicologica dello studente.

* **La Filosofia "No Judgment Zone" (Ambiente Protetto):** Molti studenti provano terrore reverenziale verso il docente universitario e si vergognano di fare domande stupide o esitare nei ricevimenti. RetainMind instaura una relazione di assoluta sicurezza emotiva: l'agente è incoraggiante, rigoroso ma mai denigratorio.
* **Voce Calibrata ed Empatica:** La voce dipende dalla modalità e dai provider configurati: cascaded è predefinita, Gemini Live opzionale; naturalezza e latenza vanno misurate sui dispositivi target.
* **Trasparenza Diagnostica:** Il report può mostrare trascrizione, progressi e stime BKT secondo le funzionalità attualmente esposte dall'app.
* **Onboarding Automatizzato & Frictionless:** Caricamento immediato del PDF o delle slide e generazione automatica dell'albero dei concetti e del piano d'esame senza configurazioni tecniche richieste all'utente finale.

---

### 5. Revenue Streams (Flussi di Ricavi)

La sostenibilità economica si fonda su un modello ibrido ad alto margine lordo e ricorrenza predicibile.

```
                  ┌──────────────────────────────────────────────────┐
                  │            REVENUE STREAMS RETAINMIND            │
                  └─────────┬──────────────────────────────┬─────────┘
                            │                              │
                            ▼                              ▼
                 ┌──────────────────────┐      ┌──────────────────────┐
                 │     SEGMENTO B2C     │      │     SEGMENTO B2B     │
                 └──────────┬───────────┘      └──────────┬───────────┘
                            │                             │
          ┌─────────────────┴───────────────┐             ├──────────────────────────────┐
          ▼                                 ▼             ▼                              ▼
┌──────────────────┐              ┌──────────────────┐ ┌──────────────────┐   ┌──────────────────┐
│  Tier Pro Sub    │              │ Pack Crediti     │ │ Licenza Annuale  │   │ Custom Academy   │
│  (14,99 €/mese   │              │ Pay-Per-Exam     │ │ Ateneo SaaS      │   │ Scuole Forensi/  │
│  o 39,99 €/sess) │              │ (9,99 € / 5 es.) │ │ (60-120 €/stud)  │   │ Med (Enterprise) │
└──────────────────┘              └──────────────────┘ └──────────────────┘   └──────────────────┘
```

#### A. Flussi di Ricavo B2C (Consumer)
1. **Abbonamento Ricorrente "RetainMind Pro" (Subscription):**
   * **Target:** Studenti universitari costanti durante tutto l'anno accademico.
   * **Pricing:** 14,99 € / mese oppure 99,00 € / anno (sconto ~45%).
   * **Incluso:** Minuti di conversazione vocale illimitati, caricamento di dispense e libri illimitati, persistenza dello storico delle iterazioni, report comparativi longitudinali ($\Delta\text{Mastery}$) ed esportazione delle trascrizioni.
2. **Pass Sessione d'Esame (Seasonal Pass):**
   * **Target:** Studenti che concentrano lo studio nei periodi critici (Gennaio-Febbraio, Giugno-Luglio, Settembre).
   * **Pricing:** 39,99 € / trimestre (one-off senza rinnovo forzato).
3. **Pacchetti a Consumo "Crediti Simulazione":**
   * **Target:** Utenti occasionali o studenti che devono sostenere un singolo esame specifico.
   * **Pricing:** 9,99 € per 5 ore di esame simulato completo con diagnosi BKT.

#### B. Flussi di Ricavo B2B (Istituzionale & Enterprise)
1. **SaaS Istituzionale per Atenei (Campus License):**
   * Contratto annuale per ateneo o facoltà, calcolato sul numero di immatricolati attivi (range indicativo: 40 € - 80 € a studente/anno per grandi atenei).
   * Include integrazione documentale con le biblioteche/materiali d'ateneo e dashboard aggregata e anonimizzata per i docenti.
2. **Accademie di Preparazione Professionale (Enterprise Setup + SaaS):**
   * Canone annuale per scuole di formazione forense o medica (da 5.000 € a 25.000 €/anno) comprensivo di sviluppo ontologie custom sui bandi di concorso e supporto dedicato.

---

### 6. Key Resources (Risorse Chiave)

Le risorse chiave garantiscono il vantaggio competitivo e l'eccellenza dell'esperienza d'uso.

#### Risorse Tecnologiche e Proprietà Intellettuale
* **Pipeline Vocale Real-Time:** Backend FastAPI/Pipecat con WebSocket PCM per Flutter e signaling SmallWebRTC opzionale; le prestazioni dipendono da provider e dispositivo.
* **Architettura Dual GraphRAG:**
  * **Neo4j:** Gestisce l'ontologia delle dipendenze concettuali (`ConceptNode`, relazioni `REQUIRES`, `CAUSES`, `CONTRASTS_WITH`), permettendo la navigazione topologica dei prerequisiti.
  * **Qdrant:** Vettore ad alte prestazioni con indicizzazione HNSW per il recupero di passaggi di "Ground Truth" con cui validare la correttezza tecnica.
* **Algoritmo BKT (Bayesian Knowledge Tracing):** Modello matematico che calcola probabilisticamente la padronanza latente del concetto senza ricorrere a banali score statici.
* **FSM Pedagogica:** Finite State Machine con transizioni rigorose (`EXPLORATION`, `CAUSAL_NARROWING`, `SCAFFOLDING`, `CONCEPTUAL_COLLISION`, `PREREQUISITE_FALLBACK`) che impediscono all'AI di perdersi in chiacchiere inconcludenti.
* **Valutazione delle Risposte (`ResponseEvaluator`):** Confronto euristico delle trascrizioni con i punti attesi nel piano; non è una misurazione acustica validata.

#### Risorse Umane e Competenze
* Ingegneri specializzati in Audio Streaming & WebRTC a bassissima latenza.
* Specialisti di Natural Language Processing, Graph Databases e Prompt Engineering per modelli multimodali.
* Esperti di scienze dell'apprendimento cognitivo e psicometria per la calibrazione dei parametri BKT.

---

### 7. Key Activities (Attività Chiave)

Le attività critiche necessarie per creare, distribuire e mantenere la proposta di valore.

#### 1. Ottimizzazione della Latenza e della Fluidità Vocale
* Misurazione della latenza per provider, trasporto e dispositivo, con obiettivi stabiliti sulla base dei benchmark.
* Miglioramento della gestione delle interruzioni e della riproduzione audio in base ai riscontri reali.

#### 2. R&D sull'Ingegneria Pedagogica e Valutativa
* Calibrazione dei parametri probabilistici del BKT ($P(L_0)$, $P(T)$, $P(S)$, $P(G)$) sulle diverse discipline per evitare sia l'eccessiva severità che l'eccessiva indulgenza.
* Miglioramento continuo delle heuristcs di scaffolding affinché l'AI fornisca indizi progressivi sempre più raffinati.

#### 3. Sviluppo del Pipeline di Ingestion Documentale
* Miglioramento del parser per i formati supportati; OCR per materiali scansionati è un'evoluzione da valutare.
* Sviluppo di estrattori di grafi concettuali capaci di costruire ontologie ad alta coerenza logica anche da dispense universitarie disordinate o frammentate.

#### 4. Gestione Infrastrutturale e Affidabilità Cloud
* Manutenzione dei cluster ad alta disponibilità per database a grafo (Neo4j) e database vettoriali (Qdrant).
* Gestione delle sessioni audio concorrenti e dimensionamento del server FastAPI/Pipecat.

#### 5. Marketing, Community Engagement & Customer Support
* Presidio attivo delle comunità studentesche universitarie durante le finestre d'esame.
* Raccolta e analisi dei feedback d'uso per individuare tempestivamente attriti nell'interazione vocale.

---

### 8. Key Partners (Partner Chiave)

La rete di partnership strategiche consente a RetainMind di concentrarsi sulla propria logica di business e pedagogica senza reinventare l'infrastruttura fondamentale.

* **Pipecat e provider di hosting:** Componenti del runtime vocale e dell'infrastruttura applicativa; SmallWebRTC è disponibile per signaling WebRTC.
* **Google (generazione piani e Gemini Live opzionale):** Il modello predefinito per piani e materiali da argomento è `gemini-3.5-flash-lite`; il modello vocale è configurabile separatamente.
* **Provider cascaded (Deepgram, ElevenLabs e altri):** Servizi configurabili per STT, LLM e TTS nella pipeline predefinita.
* **Database Vendors (Neo4j & Qdrant):** Partner tecnologici per il data storage a grafo e vettoriale ad alte prestazioni.
* **Università Pilota e Docenti Accademici:** Docenti illuminati e dipartimenti innovativi disposti a sperimentare RetainMind come strumento ufficiale di supporto al tutorato per corsi ad alta mortalità d'esame.
* **Associazioni Studentesche e Collettivi Universitari:** Canali preferenziali per la diffusione capillare del servizio e l'organizzazione di workshop di preparazione all'esame.

---

### 9. Cost Structure (Struttura dei Costi)

L'analisi dei costi operativi e di sviluppo mette in luce la scalabilità del modello e le principali voci di spesa.

#### A. Costi Variabili di Inferenza e Computing (Direttamente proporzionali all'uso)
* **Costi dei modelli vocali e LLM:** Dipendono dai servizi STT, LLM e TTS attivati; Gemini Live è opzionale.
* **Costi di Embedding e Ingestion:** Dipendono dall'implementazione configurata; gli embedding sono mock per default.
* **Costi di Traffico Audio:** Traffico PCM via WebSocket per Flutter o WebRTC se utilizzato.

#### B. Costi Fissi e Semi-Variabili di Infrastruttura
* **Hosting Cluster Database:** Server dedicati o istanze cloud managed per Neo4j Aura / cluster Neo4j e Qdrant Cloud.
* **Hosting FastAPI/Pipecat:** Costi dell'applicazione e del trasporto audio.
* **Storage e Backup:** Memorizzazione sicura dei grafi di conoscenza utente, vettori e snapshot delle sessioni (`session_state.json`).

#### C. Costi Operativi, di Ricerca e Sviluppo (R&D)
* Compensi per il team di sviluppo software, data engineer e specialisti di voice AI.
* Spese per l'esecuzione di suite di test automatizzati (CI/CD, regression testing dei flussi d'esame).

#### D. Costi di Marketing e Vendita
* Budget pubblicitario per l'acquisizione studenti nei periodi pre-sessione (Campagne TikTok, Instagram, Google Ads).
* Materiale promozionale e partnership con le associazioni universitarie.

#### E. Costi di Conformità, Privacy e Sicurezza (GDPR)
* Audit di conformità per il trattamento dei dati vocali biometrici degli studenti, garantendo che le tracce audio non vengano conservate in modo persistente se non richiesto, in ossequio al GDPR.

---

## 📊 Sintesi di Redditività e Vantaggio Competitivo

| Metrica / Aspetto | Posizionamento RetainMind | Vantaggio rispetto ai Competitor (Anki / Tutor Umani) |
| :--- | :--- | :--- |
| **Costo orario per lo studente** | $\approx 0,20 - 0,50$ € / ora (in abbonamento) | Rispetto ai 30–50 €/ora di un tutor umano privato, il risparmio per la famiglia è del **98%**. |
| **Profondità pedagogica** | Valutazione multi-hop, BKT, RCA | Rispetto ad Anki (memorizzazione atomica), allena l'argomentazione e il ragionamento causale. |
| **Scalabilità del business** | Margine lordo $> 75\%$ su abbonamenti software | Costi marginali legati unicamente alle API di inferenza vocale, che mostrano un trend storico di costante ribasso. |
| **Fattore "Defensibility" (Moat)** | Ontologia integrata GraphRAG + BKT + Voice Agent | Elevate barriere all'entrata: combinazione complessa di WebRTC real-time, grafo ontologico e pedagogia FSM. |
