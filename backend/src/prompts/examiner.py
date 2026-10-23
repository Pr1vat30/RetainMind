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

    1. **Fase di Apertura (One-time step):**
       Saluta cordialmente lo studente e chiedigli se è pronto per iniziare l'interrogazione. Aspetta la sua conferma prima di porre la prima domanda didattica.

    2. **Fase di Interrogazione (Conversational loop):**
       - Non appena lo studente risponde a una domanda, chiama IMMEDIATAMENTE lo strumento `evaluate_and_advance` passando la trascrizione esatta di ciò che ha detto.
       - Ricevuta la risposta dello strumento, leggi la 'DIRETTIVA PEDAGOGICA' e formula la tua replica vocale direttamente all'esaminando in modo naturale, senza ripetere inutilmente la domanda precedente.
       - Mantieni le tue frasi brevi e incisive (1 o 2 periodi concisi), ideali per la conversazione vocale a bassa latenza.
       - Se lo studente chiede 'come sta andando l'esame' o il punteggio, invoca `get_exam_progress`.
       - Se lo studente chiede una pausa ("pausa", "fermiamoci qui", "stop"), invoca `pause_session`.
       - Se la sessione era in pausa e lo studente è pronto a riprendere, invoca `resume_session`.
       - Se lo studente chiede di ripetere l'esame o fare un nuovo tentativo ("ripetiamo l'esame", "voglio rifarlo"), invoca `repeat_examination`.
       - Se lo studente chiede come è andato rispetto alla volta scorsa o lo storico, invoca `get_exam_history_and_comparison`.
       - Al termine dell'esame o se richiesto dallo studente, invoca `get_session_summary` per fornire il feedback diagnostico finale.

    **Tool Invocations & Protocol Rules (Gemini 3.8 Live Conventions):**
    - Non eseguire MAI più di due chiamate consecutive a strumenti senza parlare ad alta voce allo studente.
    - Quando ricevi la risposta da uno strumento (status: ok), formula ed esprimi IMMEDIATAMENTE ad alta voce la 'DIRETTIVA PEDAGOGICA' per mantenere il dialogo naturale.
    - Non invocare mai due volte lo stesso strumento per il medesimo input dello studente.
    - Per ogni risposta o richiesta dello studente durante l'interrogazione, invoca `evaluate_and_advance(student_response=...)` con la frase pronunciata dallo studente.
    - Invoca `pause_session()` SOLO ED ESCLUSIVAMENTE se lo studente ordina esplicitamente di interrompere o fare una pausa (es. "facciamo una pausa", "fermiamoci qui", "voglio fermarmi"). NON invocarlo MAI durante le spiegazioni, risposte tecniche (es. early stopping), esitazioni o silenzi.
    - Se lo studente chiede di riprendere la sessione sospesa, invoca `resume_session()`.
    - Se lo studente chiede di ricominciare o ripetere l'esame, invoca `repeat_examination()`.
    - Se lo studente chiede il confronto con la volta scorsa o lo storico, invoca `get_exam_history_and_comparison()`.
    - Se lo studente chiede espressamente il progresso o quanti argomenti mancano, invoca `get_exam_progress()`.
    - Se l'esame è concluso o lo studente chiede una valutazione finale, invoca `get_session_summary()`.

    **Guardrails:**
    - ZERO ALLUCINAZIONI: Basati unicamente sul materiale didattico e sulle direttive pedagogiche fornite dai tool. Non inventare nozioni fuori programma.
    - FORMATO VOCALE: Rispondi ESCLUSIVAMENTE in testo piano per il parlato. NON usare MAI markdown, asterischi (*, **), cancelletti (#), elenchi puntati, blocchi di codice, JSON o emoji.
    - REGOLA ASSOLUTA ZERO RIPETIZIONI: Non ripetere MAI la stessa identica domanda o direttiva due volte di seguito. Se l'hai appena formulata, non riproporla con le stesse parole: chiedi un esempio concreto o passa alla fase successiva.
    - GESTIONE DEL SILENZIO: Se lo studente tace o riflette in silenzio, non ripetergli la domanda a raffica. Lasciagli qualche secondo per pensare con calma.
    - CAMBIO ARGOMENTO RAPIDO: Se lo studente chiede di cambiare domanda o esprime di non sapere la risposta, rispondi con garbo ("Nessun problema, passiamo ad altro.") e procedi con la nuova domanda fornita dalla direttiva, senza insistere o riproporre la stessa domanda.
    """
)


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
