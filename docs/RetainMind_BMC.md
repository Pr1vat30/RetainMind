# Business Model Canvas — RetainMind

**Nome del Progetto:** RetainMind — Assistente Vocale AI per Studio e Simulazioni Orali  
**Laurea Magistrale in Informatica:** Università degli Studi di Salerno  
**Corso:** Enterprise Mobile Application Development  
**Framework di Riferimento:** The 9 Building Blocks of the Business Model Canvas (Alexander Osterwalder & Yves Pigneur)  

---

### Team Members
| Nome | Cognome | Acronimo | Contatto |
| :--- | :--- | :--- | :--- |
| Salvatore | Nocera | SN | s.nocera7@studenti.unisa.it |
| Pietro | Pascarella | PP | p.pascarella@studenti.unisa.it |

### Revision History
| Data | Versione | Autori | Descrizione |
| :--- | :--- | :--- | :--- |
| 21/10/2026 | 0.1 | SN | Prima stesura |
| 25/10/2026 | 0.2 | PP | Revisione file e allineamento all'architettura attuale |

---

## 1. Introduzione

Il documento presenta la strategia di business di **RetainMind**, illustrandone il modello economico e il posizionamento sul mercato. L'analisi si basa sul Business Model Canvas, uno strumento che permette di descrivere in modo chiaro come un progetto crea valore, lo offre ai propri utenti e genera ricavi.

RetainMind nasce per migliorare la preparazione agli esami orali universitari attraverso l'intelligenza artificiale e l'interazione vocale real-time. L'obiettivo è offrire agli studenti un supporto personalizzato che li aiuti a comprendere a fondo gli argomenti e a sviluppare la capacità di esporli con sicurezza e rigore argomentativo.

Per trasformare questa idea in un progetto sostenibile, è necessario definire una strategia che tenga conto sia degli aspetti tecnologici sia delle esigenze del mercato. Il documento è suddiviso in:

* **Sintesi del modello:** una panoramica sintetica dei nove blocchi del modello di business, pensata per facilitarne la consultazione e la rappresentazione grafica (come sintetizzato nel modello allegato).
* **Approfondimento:** un'analisi più dettagliata di ciascun blocco, che approfondisce le caratteristiche, il mercato di riferimento, i canali e la sostenibilità economica del progetto.

---

## 2. Sintesi del Modello

Questa parte presenta la sintesi dei 9 blocchi del Business Model Canvas di RetainMind. Ogni sezione sintetizza in modo puntuale le varie strategie, consentendo un utilizzo immediato nei report esecutivi, nelle schede di valutazione d'investimento e nei canali di disseminazione verso i docenti e gli organi accademici.

```
┌─────────────────────────┬─────────────────────────┬─────────────────────────┬─────────────────────────┬─────────────────────────┐
│ 8. KEY PARTNERS         │ 7. KEY ACTIVITIES       │ 1. VALUE PROPOSITIONS   │ 4. CUSTOMER RELATIONS   │ 2. CUSTOMER SEGMENTS    │
│                         │                         │                         │                         │                         │
│ • Cloud & AI Providers: │ • Ottimizzazione        │ • Simulazione Realistica│ • Interazione Vocale    │ • Studenti Universitari:│
│   Google Cloud Platform   │   Latenza Vocale:       │   full-duplex su WebRTC   │   empatica, socratica     facoltà ad alta         │
│   (Gemini 3.8 Live &      │   buffer audio e AEC    │   con latenza sub-sec   │   e non giudicante      │   densità orale         │
│   Gemini 3.5 Flash Lite)│ • Evoluzione Pedagogica │ • Valutazione e         │ • Esperienza Self-      │   (Medicina, Legge,     │
│   e framework Pipecat   │   e Calibrazione BKT    │   Scaffolding guidato   │   Service & zero setup  │   Ingegneria, STEM)     │
│ • Database Vendors:     │ • Ingegnerizzazione     │ • Root Cause Analysis   │ • Trasparenza           │ • Candidati a Concorsi: │
│   Neo4j Aura (Grafo) e  │   dell'Ingestion        │   (RCA) sulle lacune    │   diagnostica totale    │   magistratura, esami   │
│   Qdrant Cloud (Vettori)│   multiformato          │ • Tracciamento dinamico │   (BKT e mappe)         │   di stato, selezioni   │
│ • Ecosistema Accademico:│ • Manutenzione & Scale  │   competenze (BKT)      │ • Privacy-First &       │ • Atenei e Dipartimenti:│
│   docenti, tutor, Cds e │   Cloud (FastAPI)       │ • Abbattimento ansia da │   GDPR-compliant        │   tutorato e ritenzione │
│   rappresentanti        │ • Marketing & Community │   esame e allenamento   │                         │ • Enti di Formazione &  │
│ • Case Editrici e       │   Engagement            │ • Grounding su dispense │                         │   Master Privati        │
│   Piattaforme Appunti   │                         │   e materiali propri    │                         │                         │
├─────────────────────────┼─────────────────────────┤                         ├─────────────────────────┼─────────────────────────┤
│ 6. KEY RESOURCES        │                         │                         │ 3. CHANNELS             │                         │
│                         │                         │                         │                         │                         │
│ • Voice Agent Backend:  │                         │                         │ • Client Cross-Platform │                         │
│   FastAPI + Pipecat,    │                         │                         │   Flutter (WebRTC)      │                         │
│   SmallWebRTC default   │                         │                         │ • CLI per PowerUsers    │                         │
│ • Dual GraphRAG:        │                         │                         │ • Passaparola nei corsi │                         │
│   Grafo Ontologico      │                         │                         │   e community studio    │                         │
│   (Neo4j) + Vector      │                         │                         │ • Social & Short-Form   │                         │
│   Store (Qdrant)        │                         │                         │   Video (TikTok, IG)    │                         │
│ • Algoritmi Core:       │                         │                         │ • Accordi Istituzionali │                         │
│   Modello BKT e FSM a   │                         │                         │   con Atenei (B2B)      │                         │
│   5 stati pedagogici    │                         │                         │                         │                         │
├─────────────────────────┴─────────────────────────┴─────────────────────────┴─────────────────────────┴─────────────────────────┤
│ 9. COST STRUCTURE                                                           │ 5. REVENUE STREAMS                                │
│                                                                             │                                                   │
│ • Costi Variabili Inferenza AI (Gemini 3.8 Live, Gemini 3.5 Flash Lite)     │ • B2C Abbonamento Freemium: 14,99 €/mese o 99 €/anno              │
│ • Server Hosting & Banda WebRTC (FastAPI, WebRTC Media Gateway)             │ • B2C Seasonal Pass Trimestrale: 39,99 € senza rinnovo            │
│ • Gestione Cluster Database Managed (Neo4j Aura, Qdrant Cloud)              │ • B2C Pacchetti Crediti Pay-per-Use: 9,99 € per 5 esami           │
│ • R&D, Ingegneria Software e Sviluppo Modelli                               │ • B2B Licenze Campus Atenei: 40 € - 80 € a studente/anno          │
│ • Marketing Accademico, Partnership e Community Building                    │ • B2B Piani Custom Enterprise: 5.000 € - 25.000 €/anno + setup   │
│ • Spese Legali per Privacy, Protezione Dati Vocali e GDPR                   │                                                   │
└─────────────────────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────┘
```

### 2.1. Value Propositions
La proposta di valore di RetainMind si focalizza sulla risoluzione delle criticità della preparazione agli esami orali dell'universitario. Integrando intelligenza artificiale conversazionale full-duplex e solide basi pedagogiche, l'offerta si articola nei seguenti punti cardine:
* **Simulazione Realistica:** Sessioni vocali real-time basate su Pipecat con trasporto WebRTC predefinito, latenza fluida sub-secondo e gestione naturale delle interruzioni spontanee.
* **Valutazione e Scaffolding:** Valutazione delle risposte rispetto ai punti attesi nel piano d'esame; il sistema guida lo studente fornendo indizi progressivi e domande mirate anziché semplici giudizi.
* **Root Cause Analysis (RCA):** Navigazione all'indietro delle relazioni concettuali di dipendenza nel grafo ontologico, risalendo ai nodi propedeutici non compresi per sanare i problemi alla radice.
* **Tracciamento Competenze:** Stima della padronanza tramite Bayesian Knowledge Tracing (BKT), depurata da scivoloni accidentali o intuizioni casuali, per un monitoraggio affidabile.
* **Superamento Ansia da Esame:** Ambiente di prova privato, accessibile h24, privo di ansia reverenziale verso il docente e completamente privo di giudizio punitivo o sociale.
* **Grounding su Materiali Propri:** Generazione dell'interrogazione e delle verifiche rigorosamente ancorate ai materiali caricati dallo studente (dispense, PDF, appunti, slide, Markdown).

### 2.2. Customer Segments
L'analisi dei segmenti identifica i gruppi di utenti e istituzioni per i quali la simulazione orale rappresenta una risposta al superamento degli esami o alla riduzione dello stress accademico:
* **Studenti Universitari:** Studenti che affrontano percorsi di studio impegnativi, soprattutto nelle facoltà e nei corsi in cui gli esami orali hanno un peso rilevante (Medicina, Giurisprudenza, Ingegneria, STEM).
* **Candidati a Concorsi:** Professionisti e candidati a concorsi pubblici che necessitano di un supporto per prepararsi a prove selettive, esami di abilitazione professionale e colloqui orali.
* **Atenei e Dipartimenti:** Università e dipartimenti interessati a ridurre l'abbandono degli studi, supportare gli studenti in difficoltà e offrire servizi di tutorato continuativo su larga scala.
* **Enti di Formazione:** Scuole e organizzazioni formative che desiderano integrare strumenti di intelligenza artificiale nei propri percorsi didattici per offrire un supporto personalizzato.

### 2.3. Channels
L'ecosistema dei canali presidia sia l'infrastruttura di erogazione tecnologica, sia le leve di crescita organica e di contrattualizzazione istituzionale:
* **Canali di Erogazione Diretta:** Client cross-platform in Flutter con WebRTC nativo (SmallWebRTC) e interfaccia da terminale (CLI) per power user e sviluppatori.
* **Canali di Acquisizione:** Gruppi di corso (Telegram, WhatsApp, Discord), campagne di short-form video su TikTok e Instagram basate su dimostrazioni d'esame reali, e partnership studentesche.
* **Canali Commerciali Istituzionali:** Interlocuzione diretta con Prorettori alla Didattica, Direttori di Dipartimento, Delegati all'Orientamento e partecipazione a conferenze accademiche sull'e-learning.

### 2.4. Customer Relationships
La relazione instaurata con l'utente è pensata per garantire supporto maieutico, sicurezza psicologica e totale trasparenza nei riscontri pedagogici:
* **Interazione Conversazionale Empatica:** Un docente AI autorevole, empatico e accogliente, che adotta il metodo maieutico senza mai assumere un atteggiamento giudicante o punitivo.
* **Esperienza Self-Service & Zero Barriere:** Caricamento drag-and-drop dei documenti didattici e avvio immediato della simulazione vocale, senza richiedere competenze di prompt engineering o configurazioni complesse.
* **Trasparenza Diagnostica e Didattica:** Piena visibilità della mappa concettuale, dei parametri di padronanza BKT e consultazione integrale della trascrizione d'esame con esportazione dei verbali.
* **Privacy-First & No Judgment Zone:** Trattamento rigoroso dei dati audio conformemente al GDPR, garantendo che le registrazioni vocali non siano conservate in modo persistente se non esplicitamente richiesto.

### 2.5. Revenue Streams
I flussi di ricavo combinano la flessibilità dell'accesso individuale con la solidità contrattuale pluriennale delle partnership istituzionali con le università o con enti privati:
* **B2C — Abbonamento Freemium:** Abbonamento ricorrente (14,99 €/mese o 99,00 €/anno) per esami orali illimitati, caricamento di volumi estesi e report diagnostici RCA approfonditi.
* **B2C — Seasonal Pass per Sessione:** Pass trimestrale one-off da 39,99 € senza rinnovo automatico, pensato specificamente per le finestre d'esame critiche (Gen-Feb, Giu-Lug, Settembre).
* **B2C — Pacchetti Crediti Pay-per-Use:** Microtransazioni (9,99 € per 5 esami completi) per gli studenti che necessitano di una verifica mirata su una singola disciplina.
* **B2B — Licenze Campus per Atenei:** Canone calcolato sul numero di iscritti attivi (40 € - 80 € a studente/anno) con integrazione sui corsi di laurea e dashboard aggregata per i docenti.
* **B2B — Piani Custom per altre Istituzioni:** Canone enterprise (5.000 € - 25.000 €/anno + setup) comprensivo di integrazione materiali dedicati e conformità ai bandi di concorso ufficiali.

### 2.6. Key Resources
Gli asset tecnologici e i vari servizi esterni che sostengono il vantaggio competitivo strutturale e la qualità didattica del servizio includono:
* **Pipeline AI Voice Agent:** Backend FastAPI orchestrato con Pipecat, trasporto WebRTC a bassa latenza; Gemini 3.8 Live predefinito e pipeline cascaded opzionale.
* **Infrastruttura Dual GraphRAG:** Grafo della conoscenza ontologico (Neo4j) per la modellazione delle relazioni concettuali e database vettoriale (Qdrant) per l'indicizzazione semantica dei documenti.
* **Algoritmi e Modelli Utilizzati:** Modello probabilistico Bayesian Knowledge Tracing (BKT) e Finite State Machine pedagogica a 5 stati.

### 2.7. Key Activities
Le attività operative e ingegneristiche fondamentali necessarie a mantenere l'eccellenza dell'esperienza e la scalabilità del software comprendono:
* **Ottimizzazione della Latenza Vocale:** Monitoraggio e compressione dei tempi di risposta vocale end-to-end, ottimizzazione dei buffer audio e del flusso di cancellazione dell'eco (AEC).
* **Evoluzione Pedagogica e Valutativa:** Calibrazione dei parametri probabilistici del BKT, perfezionamento delle euristiche di valutazione e rafforzamento dello scaffolding socratico.
* **Ingegnerizzazione dell'Ingestion:** Miglioramento continuo dei moduli di chunking e parsing dei documenti per supportare materiali didattici complessi, slide e appunti.
* **Manutenzione e Scalabilità Cloud:** Gestione dell'affidabilità dei cluster Neo4j e Qdrant, dimensionamento del server FastAPI e monitoraggio delle sessioni concorrenti.
* **Marketing & Community Engagement:** Presidio delle comunità studentesche universitarie, raccolta qualitativa dei feedback d'uso e analisi dei miglioramenti di rendimento.

### 2.8. Key Partners
La rete di partner strategici garantisce l'accesso a infrastrutture di calcolo all'avanguardia e favorisce l'adozione capillare all'interno degli atenei:
* **Provider Cloud & AI:** Google Cloud Platform (Gemini 3.5 Flash Lite per la pianificazione e Gemini 3.8 Live per la voce) ed il framework open-source Pipecat.
* **Database Vendors:** Neo4j Aura per la gestione della topologia a grafo dei concetti e Qdrant Cloud per la ricerca vettoriale ad alte prestazioni.
* **Ecosistema Accademico:** Docenti accademici sperimentatori, comitati di corso di studio, commissioni paritetiche e associazioni studentesche universitarie.
* **Editori Giuridici e Scientifici:** Case editrici universitarie e piattaforme di compendi per l'integrazione accreditata di manuali d'esame ufficiali.

### 2.9. Cost Structure
La configurazione dei costi è caratterizzata da elevata scalabilità e bassi costi marginali per utente attivo, favorendo la sostenibilità nel lungo periodo:
* **Costi Variabili di Inferenza AI:** Consumo token per generazione piani con Gemini 3.5 Flash Lite e minutaggio sessioni vocali real-time con Gemini Live.
* **Infrastruttura Server e Rete:** Hosting di server FastAPI, consumo di banda WebRTC e cluster managed Neo4j Aura e Qdrant Cloud.
* **R&D e Sviluppo Software:** Retribuzioni e compensi per il team di ingegneria AI, sviluppatori full-stack, DevOps e ricercatori didattici.
* **Marketing e Comunicazione:** Campagne promozionali mirate nelle tre settimane precedenti le finestre d'esame e partnership con associazioni studentesche.
* **Conformità Normativa e Privacy:** Spese legali per la conformità al GDPR, la sicurezza dei dati vocali biometrici e la contrattualistica istituzionale B2B.

---

## 3. Approfondimento

Questa seconda parte approfondisce i principali blocchi del modello, illustra specificità implementative dell'architettura software ed esplicita le dinamiche finanziarie che guidano la crescita di RetainMind.

### 3.1. Value Propositions
La proposta di valore di RetainMind risponde a una disfunzione dell'istruzione universitaria: la discrepanza tra lo studio passivo individuale e la performance dialettica richiesta nell'esame orale.

#### Il Problema di Fondo
Nei contesti accademici europei ed in particolare in Italia, l'esame orale rappresenta la prova più selettiva e temuta. Mentre i test scritti a risposta multipla sono ampiamente supportati da software di ripetizione (come Anki o SuperMemo basati su flashcard atomiche), nessun prodotto commerciale finora ha colmato il divario della verbalizzazione dialettica.

Nella preparazione tradizionale emergono tre criticità croniche:
* **Illusion of Competence:** Lo studente rilegge e sottolinea le dispense più volte, confondendo la familiarità visiva con l'effettiva capacità di argomentare. Quando viene invitato a esporre a voce, si trova incapace di formulare correttamente o di stabilire collegamenti logici.
* **Ansia da Prestazione:** La pressione psicologica del confronto con il docente scatena panico e blocchi cognitivi, compromettendo esami per i quali lo studente aveva studiato con dedizione.
* **Costi Ripetizioni Private:** Le lezioni private costano tra i 15 € e i 30 € all'ora, una cifra insostenibile per la maggior parte degli studenti, creando profonde disparità di accesso al successo universitario.

#### La Soluzione RetainMind
RetainMind rovescia il paradigma dell'assistente passivo trasformando l'AI in un docente esaminatore socratico, fondato su cinque innovazioni pedagogiche e tecnologiche:
* **Interrogazione Live:** Il sistema interroga attivamente, ascolta senza interrompere e replica con risposte vocali, gestendo interruzioni e cambi di ritmo come in una reale commissione d'esame.
* **Follow-up Guidati:** Il sistema confronta la risposta con i concetti cardine attesi derivati dal piano d'esame. In presenza di risposte incomplete, formula domande di follow-up graduate per sollecitare l'auto-correzione.
* **Root Cause Analysis (RCA):** Se lo studente fallisce un concetto complesso, RetainMind non si limita a registrarlo come fallimento: risale l'ontologia delle dipendenze per verificare e sanare eventuali lacune sui concetti collegati ad esso.
* **Session Management:** Supporto nativo per la pausa vocale, mantenimento del contesto e possibilità di ripetere le simulazioni con ricalibrazione automatica sui nodi risultati deboli nelle sessioni precedenti.

### 3.2. Customer Segments
La strategia di segmentazione di RetainMind si basa su due canali: la vendita diretta agli studenti (B2C) e le collaborazioni con atenei ed enti di formazione (B2B).

#### Segmento B2C Primario: Studenti Universitari
Rappresenta il target di mercato a più alta propensione all'acquisto spontaneo:
* **Medicina e Professioni Sanitarie:** Materie con molti contenuti e concetti complessi, che richiedono una preparazione approfondita e una buona capacità di esposizione orale.
* **Giurisprudenza:** Materie che richiedono la conoscenza rigorosa della terminologia giuridica e la capacità di collegare e argomentare concetti e norme.
* **Ingegneria e Informatica:** Corsi che prevedono la comprensione di principi teorici, algoritmi e sistemi complessi, verificati attraverso esami orali approfonditi.
* **Istituti e Facoltà STEM:** Discipline come Fisica, Matematica e Chimica, che richiedono di comprendere e spiegare teoremi, dimostrazioni e modelli scientifici.

#### Segmento B2C Secondario: Post-Graduate & Concorsi
Segmento caratterizzato da un'elevata disponibilità a pagare per prove abilitanti ad alto impatto professionale:
* **Professioni Giuridiche:** Candidati alla prova orale per l'abilitazione forense o all'esame per la magistratura.
* **Specializzazioni Mediche:** Medici neolaureati in preparazione intensiva per il concorso nazionale SSM.
* **Concorsi Pubblici Selettivi:** Partecipanti a concorsi pubblici ad alto profilo (Agenzia delle Entrate, Banca d'Italia, Ministeri).

#### Segmento B2B: Atenei e Dipartimenti Universitari
Le università affrontano sfide crescenti legate ai tassi di abbandono e all'efficacia del tutorato:
* **Problemi per le Università:** Elevati tassi di drop-out tra il primo e il secondo anno e accumulo di studenti fuori corso bloccati su singoli esami-scoglio propedeutici.
* **Opportunità per gli Atenei:** Fornire uno strumento di tutorato vocale h24 a costo marginale scalabile, sgravando i docenti nei ricevimenti e ottenendo un pre-screening analitico delle aree di maggiore criticità per gli studenti.

### 3.3. Channels
I canali gestiscono l'erogazione tecnologica dell'assistente e la strategia di penetrazione commerciale nei vari segmenti di mercato, favorendo l'acquisizione e la fidelizzazione degli utenti.

#### Delivery Channels
La fruizione è disegnata per garantire affidabilità tecnologica su qualsiasi dispositivo:
* **Interfaccia in Flutter:** Client cross-platform che utilizza SmallWebRTC per lo streaming audio full-duplex a bassa latenza, con sincronizzazione grafica dello stato dell'esame e della trascrizione.
* **CLI per PowerUsers:** Interfaccia da terminale (`session_cli.py`) per power user, studenti d'informatica e ricercatori che desiderano eseguire simulazioni ed esportare log in formato Markdown.

#### Consumer Growth
La crescita nel canale consumer sfrutta le dinamiche tipiche dell'ambiente universitario:
* **Passaparola Accademico:** Quando uno studente supera un esame notoriamente bloccante grazie a RetainMind, la voce si diffonde rapidamente nei gruppi Telegram e WhatsApp del corso.
* **Social & Short-Form Video:** Campagne su TikTok, Instagram Reels e YouTube basate su simulazioni orali reali, che mostrano funzionalità, vantaggi e strategie per superare i blocchi mentali.
* **Ambassador e Associazioni:** Collaborazione con i rappresentanti degli studenti e le associazioni universitarie per workshop informativi ed eventi di orientamento.

#### Canali Commerciali
La vendita istituzionale segue un percorso accademico formale:
* **Vendita Diretta:** Incontri istituzionali e progetti pilota con Prorettori alla Didattica, Delegati all'Innovazione Digitale e Presidenti di Corso di Laurea.
* **Fiere e Conferenze:** Partecipazione a fiere e convegni internazionali sull'e-learning, la tecnologia educativa e l'innovazione della didattica universitaria.

### 3.4. Customer Relationships
La relazione con l'utente è legata alla sua esperienza emotiva e si fonda su quattro pilastri, volti a favorire fiducia, motivazione e continuità nell'apprendimento:
* **'No Judgment Zone':** Molti studenti provano soggezione verso il docente e si vergognano di fare domande o esporre concetti. RetainMind garantisce un ambiente privo di giudizio, rigoroso ma incoraggiante, dove sbagliare fa parte dell'apprendimento.
* **Voce Empatica:** L'agente vocale adotta una voce naturale ed empatica, capace di modulare l'intonazione e incoraggiare lo studente nelle fasi di stallo o esitazione.
* **Trasparenza Diagnostica:** Accesso completo alla mappa dei concetti, alla stima della padronanza BKT e alle motivazioni della Root Cause Analysis, evitando la logica a scatola chiusa.
* **Onboarding Automatizzato:** Aggiunta dei documenti didattici e generazione del piano d'esame in pochi secondi, senza richiedere prompt engineering o settaggi manuali.

### 3.5. Revenue Streams e Piano di Prezzo
Il modello economico si basa su un'elevata marginalità e su entrate stabili e prevedibili, strutturate per incontrare sia le disponibilità dello studente sia i budget degli atenei.

| Segmento | Tipologia | Prezzo | Caratteristiche |
| :--- | :--- | :--- | :--- |
| **B2C Consumer** | Abbonamento | 14,99 € / mese<br>99,00 € / anno | Simulazioni vocali illimitate, caricamento PDF illimitato, storico completo e report diagnostici RCA. |
| **B2C Consumer** | Pass Sessione | 39,99 € / trimestre (senza rinnovo) | Accesso full concentrato nelle finestre d'esame universitarie (Gen-Feb, Giu-Lug, Settembre). |
| **B2C Consumer** | Crediti a Consumo | 9,99 € per 5 simulazioni | Per studenti occasionali che necessitano di verificare la preparazione su una singola materia o esame. |
| **B2B Istituzionale** | Licenza Ateneo | 40 € - 80 € a studente/anno | Adozione su interi corsi di laurea con dashboard analitica aggregata per docenti e presidi. |
| **B2B Enterprise** | Offerta Custom | 5.000 € - 25.000 € ogni anno + setup | Scuole, accademie ed enti privati con ontologie personalizzate sui bandi ufficiali e supporto SLA dedicato. |
