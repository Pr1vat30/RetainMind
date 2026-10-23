"""Oral Examination Session Management CLI.

Allows controlling and querying the oral examination session directly from the terminal:
- View real-time status and progress: `uv run python src/session_cli.py status`
- Pause an ongoing session: `uv run python src/session_cli.py pause [--reason "motivo"]`
- Resume a paused session: `uv run python src/session_cli.py resume`
- Repeat the exam as a new iteration: `uv run python src/session_cli.py repeat [--no-adapt]`
- Inspect longitudinal history: `uv run python src/session_cli.py history`
- Compare performance with previous trials: `uv run python src/session_cli.py compare`
- View full diagnostic report and RCA: `uv run python src/session_cli.py report`
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

from assessment import SessionService


def print_banner(title: str) -> None:
    print("\n" + "═" * 70)
    print(f"🎓 {title}")
    print("═" * 70)


async def cmd_status(service: SessionService, args: argparse.Namespace) -> None:
    status = service.get_status()
    print_banner("STATO DELLA SESSIONE D'ESAME")
    if not status.get("has_active_session"):
        print("[INFO] Nessuna sessione d'esame attiva o salvata trovata.")
        print("       Avvia una sessione vocale Pipecat per iniziare.")
        return

    print(f"• ID Studente:          {status.get('student_id')}")
    print(f"• Stato Sessione:       {status.get('status')}")
    print(f"• Iterazione Corrente:  {status.get('current_iteration')}")
    print(f"• Argomento Attivo:     {status.get('current_concept_id')}")
    print(f"• Stato Pedagogico:     {status.get('pedagogical_state')}")
    print(f"• Passo del Piano:      {status.get('plan_step')}")
    print(f"• Progresso Totale:     {status.get('plan_progress_percentage')}%")
    print(f"• Turni nell'Iterazione: {status.get('turns_in_current_iteration')}")
    print(f"• Iterazioni Archiviate: {status.get('total_iterations_completed')}")
    if status.get("deferred_queue"):
        print(f"• Coda di Rinvio Ciclico: {status.get('deferred_queue')}")
    print("═" * 70 + "\n")


async def cmd_pause(service: SessionService, args: argparse.Namespace) -> None:
    print_banner("SOSPENSIONE SESSIONE D'ESAME")
    res = await service.pause(reason=args.reason or "")
    print(f"⏸️  Stato aggiornato: {res.get('status')}")
    print(f"📌  Argomento salvato: {res.get('paused_concept_id')}")
    print(f'💬  Messaggio Docente: "{res.get("spoken_directive")}"')
    print("═" * 70 + "\n")


async def cmd_resume(service: SessionService, args: argparse.Namespace) -> None:
    print_banner("RIPRESA SESSIONE D'ESAME")
    try:
        res = await service.resume()
        print(f"▶️  Stato aggiornato: {res.get('status')}")
        print(f"📌  Argomento attivo: {res.get('current_concept_id')}")
        print(f'💬  Messaggio Docente:\n   "{res.get("spoken_directive")}"')
    except FileNotFoundError as err:
        print(f"❌ Errore: {err}")
    print("═" * 70 + "\n")


async def cmd_repeat(service: SessionService, args: argparse.Namespace) -> None:
    print_banner("RIPETIZIONE DELL'ESAME (NUOVA ITERAZIONE)")
    adapt = not args.no_adapt
    res = await service.repeat(adapt=adapt)
    print(f"🔄  Nuova Iterazione Avviata: Iterazione {res.get('new_iteration')}")
    print(
        f"📁  Iterazioni Precedenti Archiviate: {res.get('total_archived_iterations')}"
    )
    print(f"🎯  Primo Argomento Target: {res.get('first_concept_id')}")
    print(
        f"⚙️  Adattamento Dinamico: {'Attivo (prioritizza lacune pregresse)' if adapt else 'Disattivato'}"
    )
    print(f'💬  Direttiva d\'Avvio:\n   "{res.get("spoken_directive")}"')
    print("═" * 70 + "\n")


async def cmd_history(service: SessionService, args: argparse.Namespace) -> None:
    print_banner("STORICO DELLE ITERAZIONI D'ESAME")
    hist = service.get_history()
    if not hist:
        print("[INFO] Nessuno storico registrato.")
        return

    for item in hist:
        iter_num = item.get("iteration")
        is_curr = item.get("is_current", False)
        tag = " [IN CORSO]" if is_curr else " [COMPLETATA]"
        print(f"\n📁 Iterazione {iter_num}{tag}:")
        if not is_curr:
            print(
                f"   • Padronanza Media: {item.get('average_mastery', 0.0) * 100:.0f}%"
            )
            print(f"   • Concetti Padroneggiati: {item.get('mastered_concepts', [])}")
            print(f"   • Concetti con Lacune:    {item.get('weak_concepts', [])}")
            print(f"   • Totale Turni Svolti:    {len(item.get('history', []))}")
        else:
            print(f"   • Stato: {item.get('status')}")
            print(f"   • Argomento Attivo: {item.get('active_concept_id')}")
            print(f"   • Turni Svolti:     {item.get('turns_completed')}")
    print("\n" + "═" * 70 + "\n")


async def cmd_compare(service: SessionService, args: argparse.Namespace) -> None:
    print_banner("CONFRONTO CON LE ITERAZIONI PRECEDENTI")
    comp = await service.compare()
    if not comp.get("has_previous_iterations"):
        print(f"[INFO] {comp.get('spoken_comparison')}")
        return

    delta = comp.get("mastery_delta", 0.0)
    delta_str = f"+{delta * 100:.0f}%" if delta >= 0 else f"{delta * 100:.0f}%"
    print(f"• Confronto con Iterazione: {comp.get('compared_iteration')}")
    print(
        f"• Padronanza Precedente:   {comp.get('previous_average_mastery', 0.0) * 100:.0f}%"
    )
    print(
        f"• Padronanza Attuale:      {comp.get('current_average_mastery', 0.0) * 100:.0f}%"
    )
    print(f"• Variazione Padronanza:   {delta_str}")
    print(f"• Concetti Recuperati:     {comp.get('recovered_concepts', [])}")
    print(f"• Lacune Persistenti:      {comp.get('persistent_weak_concepts', [])}")
    print(f"• Nuovi Padroneggiati:     {comp.get('newly_mastered_concepts', [])}")
    print(f'\n🗣️  SINTESI DEL DOCENTE:\n   "{comp.get("spoken_comparison")}"')
    print("═" * 70 + "\n")


async def cmd_report(service: SessionService, args: argparse.Namespace) -> None:
    print_banner("REPORT DIAGNOSTICO COMPLETO & ROOT CAUSE ANALYSIS")
    rep = await service.get_diagnostic_report()
    if rep.get("total_turns", 0) == 0:
        print("[INFO] Nessun dato registrato nella sessione.")
        return

    print(f"• Totale Turni Valutati:   {rep.get('total_turns')}")
    print(f"• Padronanza Media Finale: {rep.get('average_mastery', 0.0) * 100:.0f}%")
    print(f"• Concetti Padroneggiati:  {rep.get('mastered_concepts', [])}")
    print(f"• Concetti da Consolidare: {rep.get('weak_concepts', [])}")
    print(f"• Concetti in Progresso:   {rep.get('in_progress_concepts', [])}")
    if rep.get("root_cause_analysis"):
        print("\n🔍 Root Cause Analysis (Prerequisiti Mancanti):")
        for rca in rep.get("root_cause_analysis", []):
            print(
                f"   - Lacuna su '{rca.get('failed_concept_name')}' causata dal prerequisito '{rca.get('root_cause_name')}'"
            )


async def cmd_transcript(service: SessionService, args: argparse.Namespace) -> None:
    print_banner("TRASCRIZIONE COMPLETA DELLA CONVERSAZIONE")
    turns = service.get_conversation_transcript(iteration=args.iteration)
    if not turns:
        print("[INFO] Nessuna conversazione registrata da mostrare.")
        return

    print(f"📊 Totale Scambi Trovati: {len(turns)}")
    curr_iter = None
    for t in turns:
        t_iter = t.get("iteration", 1)
        if t_iter != curr_iter:
            curr_iter = t_iter
            print(f"\n{'━' * 30} 📁 ITERAZIONE {curr_iter} {'━' * 30}\n")

        t_num = t.get("turn", "?")
        c_name = t.get("concept_name") or t.get("concept_id") or "Apertura"
        ts = t.get("timestamp", "")
        ts_display = ts.split("T")[-1][:8] if "T" in ts else ts

        ai_q = t.get("ai_question") or t.get("directive") or ""
        student_a = t.get("student_response") or t.get("transcript") or ""
        eval_res = t.get("evaluation") or t.get("evaluation_result") or "N/A"
        delta = t.get("mastery_delta")
        delta_str = f" ({delta:+.2f})" if delta is not None else ""
        state = t.get("pedagogical_state") or t.get("next_state") or ""

        print(f"🔹 [TURNO {t_num}] {ts_display} | Argomento: {c_name}")
        if ai_q:
            print(f'   👨‍🏫 Docente AI: "{ai_q}"')
        if student_a:
            print(f'   🎓 Studente:   "{student_a}"')
        print(f"   📋 Esito:      [{eval_res}]{delta_str} | Stato: {state}\n")

    if args.export:
        out_path = Path(args.export)
        md_content = service.export_transcript_markdown(iteration=args.iteration)
        out_path.write_text(md_content, encoding="utf-8")
        print(f"💾 Trascrizione esportata con successo in: {out_path.resolve()}\n")

    print("═" * 70 + "\n")


async def cmd_events(service: SessionService, args: argparse.Namespace) -> None:
    print_banner("REGISTRO EVENTI DI SESSIONE (CONSOLE / LOCAL / CLOUD)")
    events = service.get_events(limit=args.limit)
    if not events:
        print("[INFO] Nessun evento registrato finora.")
        return

    print(f"📊 Ultimi {len(events)} Eventi Registrati:")
    for ev in events:
        ts = ev.get("timestamp", "")
        ts_display = ts.split("T")[-1][:8] if "T" in ts else ts
        mode = ev.get("execution_mode", "UNKNOWN").upper()
        ev_type = ev.get("event_type", "GENERIC")
        cid = ev.get("concept_id") or "N/A"
        data = ev.get("data", {})
        print(f"📌 [{ts_display}][{mode}][{ev_type}] (Concept: {cid})")
        for k, v in data.items():
            print(f"   • {k}: {v}")
        print()

    print("═" * 70 + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Gestione da terminale della sessione d'esame orale (Status, Pausa, Ripresa, Ripetizione, Storico, Confronto, Trascrizione, Eventi)."
    )
    parser.add_argument(
        "--state-file",
        type=str,
        default="session_state.json",
        help="Percorso del file di stato della sessione (default: session_state.json)",
    )
    parser.add_argument(
        "--plan-file",
        type=str,
        default="examination_plan.json",
        help="Percorso del piano d'esame (default: examination_plan.json)",
    )
    parser.add_argument(
        "--events-file",
        type=str,
        default="session_events.jsonl",
        help="Percorso del file di registro eventi (default: session_events.jsonl)",
    )

    subparsers = parser.add_subparsers(dest="command", help="Comando da eseguire")

    # status
    subparsers.add_parser("status", help="Visualizza lo stato e il progresso corrente")

    # pause
    p_pause = subparsers.add_parser(
        "pause", help="Sospende la sessione d'esame corrente"
    )
    p_pause.add_argument(
        "--reason", type=str, default="", help="Motivazione facoltativa"
    )

    # resume
    subparsers.add_parser("resume", help="Riprende la sessione d'esame sospesa")

    # repeat
    p_repeat = subparsers.add_parser(
        "repeat", help="Riavvia l'esame come nuova iterazione con adattamento"
    )
    p_repeat.add_argument(
        "--no-adapt",
        action="store_true",
        help="Disattiva l'adattamento dinamico sulle lacune",
    )

    # history
    subparsers.add_parser(
        "history", help="Mostra lo storico di tutte le iterazioni svolte"
    )

    # compare
    subparsers.add_parser(
        "compare", help="Confronta l'iterazione attuale con la precedente"
    )

    # report
    subparsers.add_parser(
        "report", help="Genera il report diagnostico completo con RCA"
    )

    # transcript
    p_transcript = subparsers.add_parser(
        "transcript",
        help="Naviga e visualizza la trascrizione completa di domande e risposte",
    )
    p_transcript.add_argument(
        "--iteration",
        type=int,
        default=None,
        help="Filtra la trascrizione per una specifica iterazione",
    )
    p_transcript.add_argument(
        "--export",
        type=str,
        default="",
        help="Percorso file Markdown in cui esportare la trascrizione (es. transcript.md)",
    )

    # events
    p_events = subparsers.add_parser(
        "events",
        help="Visualizza il registro unificato degli eventi (console/locale/cloud)",
    )
    p_events.add_argument(
        "--limit",
        type=int,
        default=25,
        help="Numero massimo di eventi recenti da visualizzare (default: 25)",
    )

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(0)

    service = SessionService(
        state_file_path=args.state_file,
        plan_file_path=args.plan_file,
        events_file_path=args.events_file,
    )

    commands = {
        "status": cmd_status,
        "pause": cmd_pause,
        "resume": cmd_resume,
        "repeat": cmd_repeat,
        "history": cmd_history,
        "compare": cmd_compare,
        "report": cmd_report,
        "transcript": cmd_transcript,
        "events": cmd_events,
    }

    handler = commands.get(args.command)
    if handler:
        asyncio.run(handler(service, args))


if __name__ == "__main__":
    main()
