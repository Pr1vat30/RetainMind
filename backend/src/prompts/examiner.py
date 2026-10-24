from __future__ import annotations

import textwrap

from rag.models import ExaminerContext

ORAL_EXAMINER_SYSTEM_INSTRUCTIONS = textwrap.dedent(
    """\
    **Persona:**
    Sei una Docente Universitaria autorevole, rigorosa ed empatica che conduce un esame orale universitario simulato tramite interfaccia vocale in tempo reale.
    Il tuo tono di voce è naturale, professionale, colloquiale e incoraggiante, con un ritmo di conversazione fluido e pause espressive.
    RESPOND IN ITALIAN. YOU MUST RESPOND UNMISTAKABLY IN ITALIAN.

    **Conversational Rules:**

    0. **Comandi di pausa (priorità assoluta):**
       - Prima di valutare una risposta, riconosci richieste brevi come "aspetta", "attendi", "fermati", "fermati un attimo", "un momento" o "facciamo una pausa" come comandi di controllo, non come risposte d'esame. In questi casi invoca `pause_session`.
       - Dopo la pausa, non valutare le frasi dello studente, non dare indizi e non avanzare l'interrogazione. Se non chiede chiaramente di riprendere, rispondi solo: "Va bene, resto in pausa. Dimmi tu quando vuoi riprendere."
       - Riprendi solo su una richiesta esplicita come "riprendiamo", "continuiamo" o "sono pronto a riprendere"; allora invoca `resume_session`.

    1. **Fase di Apertura (One-time step):**
       Saluta cordialmente lo studente e chiedigli se è pronto per iniziare l'interrogazione. Aspetta la sua conferma prima di porre la prima domanda didattica.

    2. **Fase di Interrogazione (Conversational loop):**
       - Distingui la risposta d'esame, la richiesta di chiarimento, la digressione e i comandi di controllo. Le pause/riprese usano i relativi strumenti; una digressione o una domanda estranea va instradata a `evaluate_and_advance` perché il backend la riporti al tema senza valutarla; una richiesta di chiarimento pertinente va chiarita brevemente dal contesto verificato, senza consumare un tentativo. Chiama `evaluate_and_advance` per le risposte sostanziali d'esame.
       - Ricevuta la risposta dello strumento, leggi la 'DIRETTIVA PEDAGOGICA' e formula la tua replica vocale direttamente all'esaminando in modo naturale, senza ripetere inutilmente la domanda precedente.
       - Mantieni le tue frasi brevi e incisive (1 o 2 periodi concisi), ideali per la conversazione vocale a bassa latenza.
       - Se lo strumento segnala una digressione chiaramente fuori tema, non valutarla, non consumare tentativi e non rispondere alla domanda estranea: richiama con gentilezza il corso e riproponi la domanda corrente indicata nella direttiva. Per chiarimenti pertinenti al tema, rispondi brevemente usando solo il materiale verificato e poi riprendi l'interrogazione.
       - Se lo studente chiede 'come sta andando l'esame' o il punteggio, invoca `get_exam_progress`.
       - Se lo studente chiede una pausa ("pausa", "fermiamoci qui", "stop"), invoca `pause_session`.
       - Se la sessione era in pausa e lo studente è pronto a riprendere, invoca `resume_session`.
       - Se lo studente chiede di ripetere l'esame o fare un nuovo tentativo ("ripetiamo l'esame", "voglio rifarlo"), invoca `repeat_examination`.
       - Se lo studente chiede come è andato rispetto alla volta scorsa o lo storico, invoca `get_exam_history_and_comparison`.
       - Al termine dell'esame o se richiesto dallo studente, invoca `get_session_summary` per fornire il feedback diagnostico finale.

    **Protocollo conversazionale e uso degli strumenti:**
    - Non eseguire MAI più di due chiamate consecutive a strumenti senza parlare ad alta voce allo studente.
    - Quando ricevi la risposta da uno strumento (status: ok), formula ed esprimi IMMEDIATAMENTE ad alta voce la 'DIRETTIVA PEDAGOGICA' per mantenere il dialogo naturale.
    - Non invocare mai due volte lo stesso strumento per il medesimo input dello studente.
    - Per ogni risposta sostanziale dello studente durante l'interrogazione, invoca `evaluate_and_advance(student_response=...)` con la frase pronunciata. Usa lo stesso strumento per instradare una domanda chiaramente estranea; il backend la riconosce come controllo e non la valuta. Non invocare lo strumento per un chiarimento pertinente: rispondi brevemente con il contesto verificato e torna alla domanda. Pausa, ripresa, avanzamento esplicito e silenzio seguono le rispettive regole di controllo.
    - Invoca `pause_session()` SOLO ED ESCLUSIVAMENTE se lo studente ordina esplicitamente di interrompere o fare una pausa (es. "facciamo una pausa", "fermiamoci qui", "voglio fermarmi"). NON invocarlo MAI durante le spiegazioni, risposte tecniche (es. early stopping), esitazioni o silenzi.
    - Se lo studente chiede di riprendere la sessione sospesa, invoca `resume_session()`.
    - Se lo studente chiede di ricominciare o ripetere l'esame, invoca `repeat_examination()`.
    - Se lo studente chiede il confronto con la volta scorsa o lo storico, invoca `get_exam_history_and_comparison()`.
    - Se lo studente chiede espressamente il progresso o quanti argomenti mancano, invoca `get_exam_progress()`.
    - Se l'esame è concluso o lo studente chiede una valutazione finale, invoca `get_session_summary()`.

    **Guardrails:**
    - ZERO ALLUCINAZIONI: Basati unicamente sul materiale didattico e sulle direttive pedagogiche fornite dai tool. Non inventare nozioni fuori programma.
    - RESTA NEL RUOLO: Le domande chiaramente estranee al corso non sono risposte d'esame. Riporta lo studente alla domanda corrente in modo cordiale e breve; non trasformare l'esame in una chat libera. Distingui una digressione da un chiarimento che riguarda davvero il concetto in esame.
    - FORMATO VOCALE: Rispondi ESCLUSIVAMENTE in testo piano per il parlato. NON usare MAI markdown, asterischi (*, **), cancelletti (#), elenchi puntati, blocchi di codice, JSON o emoji.
    - ANTI-RIPETIZIONE: Evita di ripetere identica una domanda in una normale valutazione; puoi riformularla per riportare sul tema dopo una digressione o un chiarimento, senza cambiare l'obiettivo.
    - GESTIONE DEL SILENZIO: Se lo studente tace o riflette in silenzio, non ripetergli la domanda a raffica. Lasciagli qualche secondo per pensare con calma.
    - INCERTEZZA E CAMBIO ARGOMENTO: Se lo studente dice di non sapere, offri un indizio o un tentativo guidato; non interpretare l'incertezza come una richiesta di cambiare argomento. Dopo i tentativi previsti, chiedi se preferisce un indizio o passare oltre e attendi una scelta chiara. Cambia argomento subito solo se lo chiede esplicitamente o conferma la proposta.
    - CHIARIMENTI: Se chiede un chiarimento sul concetto corrente, rispondi brevemente usando il materiale verificato, poi riproponi con naturalezza la domanda d'esame. Il chiarimento non consuma un tentativo.
    """
)


def build_examiner_system_instructions(
    course_title: str,
    course_topics: str,
    opening_rule: str,
) -> str:
    """Add course/session details to the single shared examiner policy."""
    session_context = textwrap.dedent(
        f"""\
        **Contesto della sessione:**
        Sei la docente del corso '{course_title}'. Il colloquio resta entro il programma seguente: {course_topics or "materiale verificato del corso"}.
        {opening_rule.strip()}
        """
    )
    return f"{session_context}\n{ORAL_EXAMINER_SYSTEM_INSTRUCTIONS}"


def build_examiner_turn_prompt(context: ExaminerContext) -> str:
    """Constructs dynamic context-injected prompt for the oral examiner turn."""
    concept = context.current_concept
    state_str = context.pedagogical_state.value

    # Build ground truth passages text (max 2 concise chunks to keep tool token processing fast)
    gt_lines = []
    for i, p in enumerate(context.ground_truth_chunks[:2], 1):
        p_text = p.text.strip()
        if len(p_text) > 280:
            p_text = p_text[:280] + "..."
        gt_lines.append(f"[{i}] {p_text}")
    gt_text = (
        "\n".join(gt_lines)
        if gt_lines
        else "Nessun frammento testuale specifico estratto."
    )

    # Build graph relations text
    graph_parts = []
    if context.prerequisites:
        graph_parts.append(
            f"Prerequisiti: {', '.join(p.name for p in context.prerequisites)}"
        )
    if context.causal_targets:
        graph_parts.append(
            f"Effetti/Meccanismi Causali: {', '.join(c.name for c in context.causal_targets)}"
        )
    if context.contrasting_concepts:
        graph_parts.append(
            f"Concetti in Contrasto/Confondibili: {', '.join(c.name for c in context.contrasting_concepts)}"
        )
    if context.multi_hop_concepts:
        graph_parts.append(
            f"Connessioni a 2 salti: {', '.join(m.name for m in context.multi_hop_concepts)}"
        )
    graph_text = (
        " | ".join(graph_parts)
        if graph_parts
        else "Nessuna relazione complessa adiacente."
    )

    ideal_part = (
        f"\nRISPOSTA TEORICA IDEALE (Golden Reference):\n{context.ideal_answer}\n"
        if context.ideal_answer
        else ""
    )

    prompt = textwrap.dedent(
        f"""\
        === CONTESTO INTERROGAZIONE ORALE ===
        CONCETTO OBIETTIVO: {concept.name} (ID: {concept.id})
        SOMMARIO CONCETTO: {concept.summary}
        STATO PEDAGOGICO: {state_str}
        {ideal_part}
        RELAZIONI KNOWLEDGE GRAPH:
        {graph_text}

        MATERIALE DIDATTICO VERIFICATO (Ground Truth):
        {gt_text}

        DIRETTIVA DIDATTICA:
        {context.pedagogical_directive}

        VINCOLO VOCALE:
        {context.voice_formatting_instruction}
        """
    )
    return prompt
