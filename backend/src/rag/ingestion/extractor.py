"""Ontological knowledge and relationship extractor.

Extracts concept nodes, prerequisites (REQUIRES), causal links (CAUSES),
and contrast pairs (CONTRASTS_WITH) from structured JSON schemas or directly
from parsed document chunks via Gemini Multimodal / Text LLM extraction.
"""

from __future__ import annotations

import concurrent.futures
import json
import logging
import os
import re
from typing import Any

from rag.models import (
    CausalChain,
    ConceptNode,
    ConceptRelation,
    ConceptStatus,
    DocumentChunk,
    RelationType,
)

logger = logging.getLogger("agent.rag.ingestion.extractor")


class KnowledgeExtractor:
    """Extracts structured concepts, ontological relations, and causal chains."""

    @staticmethod
    def parse_structured_json(
        data: dict[str, Any] | str,
    ) -> tuple[list[ConceptNode], list[ConceptRelation], list[CausalChain]]:
        """Parse strict JSON output schema into domain models."""
        payload = json.loads(data) if isinstance(data, str) else data

        concepts: list[ConceptNode] = []
        relations: list[ConceptRelation] = []
        causal_chains: list[CausalChain] = []

        # 1. Parse concepts
        for c in payload.get("concepts", []):
            cid = c.get("id") or re.sub(r"\W+", "_", c.get("name", "").lower()).strip(
                "_"
            )
            props = c.get("properties") or {
                "ideal_answer": c.get("ideal_answer", ""),
                "expected_key_points": c.get("expected_key_points", []),
                "main_question": c.get("main_question", ""),
                "narrowing_questions": c.get("narrowing_questions", []),
                "scaffolding_hints": c.get("scaffolding_hints", []),
                "stress_test_questions": c.get("stress_test_questions", []),
                "collision_check_questions": c.get("collision_check_questions", []),
                "difficulty": c.get("difficulty", "MEDIUM"),
                "causal_targets": c.get("causal_targets", []),
            }
            node = ConceptNode(
                id=cid,
                name=c.get("name", cid),
                summary=c.get("summary", ""),
                prerequisites=c.get("prerequisites", []),
                contrasts_with=c.get("contrasts_with", []),
                status=ConceptStatus.UNTESTED,
                mastery_score=0.50,
                properties=props,
            )
            concepts.append(node)

            for prereq in node.prerequisites:
                relations.append(
                    ConceptRelation(
                        source_id=node.id,
                        target_id=prereq,
                        rel_type=RelationType.REQUIRES,
                    )
                )

            for contrast in node.contrasts_with:
                relations.append(
                    ConceptRelation(
                        source_id=node.id,
                        target_id=contrast,
                        rel_type=RelationType.CONTRASTS_WITH,
                    )
                )

        # 2. Parse explicit relations
        for r in payload.get("relations", []):
            rel_type_str = r.get("type", "DEFINES").upper()
            try:
                rel_type = RelationType(rel_type_str)
            except ValueError:
                rel_type = RelationType.DEFINES

            relations.append(
                ConceptRelation(
                    source_id=r.get("source"),
                    target_id=r.get("target"),
                    rel_type=rel_type,
                    condition=r.get("condition"),
                )
            )

        # 3. Parse causal chains
        for cc in payload.get("causal_chains", []):
            cause = cc.get("cause")
            effect = cc.get("effect")
            cond = cc.get("condition")
            causal_chains.append(
                CausalChain(cause=cause, effect=effect, condition=cond)
            )
            relations.append(
                ConceptRelation(
                    source_id=cause,
                    target_id=effect,
                    rel_type=RelationType.CAUSES,
                    condition=cond,
                )
            )

        return concepts, relations, causal_chains

    @classmethod
    def _clean_and_parse_json(
        cls,
        text: str,
        client: Any | None = None,
        model: str = "gemini-3.8-flash",
    ) -> dict[str, Any]:
        """Resiliently parse and repair JSON returned by the LLM."""
        if not text or not text.strip():
            raise ValueError("L'LLM ha restituito una risposta vuota.")

        cleaned = text.strip()
        match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", cleaned)
        if match:
            cleaned = match.group(1).strip()
        else:
            start = cleaned.find("{")
            end = cleaned.rfind("}")
            if start != -1 and end != -1 and end > start:
                cleaned = cleaned[start : end + 1]

        # 1. Direct standard parse attempt (pre-repair invalid escape sequences and trailing commas)
        cleaned_escapes = re.sub(r'\\(?![/\\\"bfnrt]|u[0-9a-fA-F]{4})', r'\\\\', cleaned)
        cleaned_escapes = re.sub(r",\s*([\]}])", r"\1", cleaned_escapes)
        initial_err: Exception | None = None
        try:
            return json.loads(cleaned_escapes)
        except json.JSONDecodeError as err:
            initial_err = err
            logger.debug(
                "Tentativo json.loads diretto necessita normalizzazione (%s). Applicazione repair...",
                err,
            )

        # 2. Repair unescaped newlines/tabs inside string literals
        repaired_lines = []
        in_string = False
        escape = False
        for ch in cleaned_escapes:
            if ch == '"' and not escape:
                in_string = not in_string
            if in_string and ch == "\n":
                repaired_lines.append("\\n")
            elif in_string and ch == "\r":
                pass
            elif in_string and ch == "\t":
                repaired_lines.append("\\t")
            else:
                repaired_lines.append(ch)
            escape = bool(ch == "\\" and not escape)
        repaired_ctrl = "".join(repaired_lines)
        repaired_ctrl = re.sub(r",\s*([\]}])", r"\1", repaired_ctrl)
        try:
            return json.loads(repaired_ctrl)
        except json.JSONDecodeError:
            pass

        # 4. AST literal evaluation if Python-like formatting
        try:
            import ast

            eval_res = ast.literal_eval(cleaned)
            if isinstance(eval_res, dict):
                return eval_res
        except Exception:
            pass

        # 5. Fast LLM repair call if client is provided
        if client is not None:
            try:
                from google.genai import types

                logger.info("Chiamata rapida di correzione sintattica JSON a Gemini...")
                repair_prompt = f"Correggi questo JSON difettoso restituendo esclusivamente il JSON valido senza markdown:\n{cleaned[:15000]}"
                repair_resp = client.models.generate_content(
                    model=model,
                    contents=repair_prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        temperature=0.0,
                        automatic_function_calling=types.AutomaticFunctionCallingConfig(
                            disable=True
                        ),
                    ),
                )
                if repair_resp and repair_resp.text:
                    return json.loads(repair_resp.text.strip())
            except Exception as repair_err:
                logger.warning(
                    "Tentativo di riparazione tramite LLM fallito: %s", repair_err
                )

        # 6. Regex fallback for individual concept objects
        concepts_match = re.search(r'"concepts"\s*:\s*\[([\s\S]*?)\]', cleaned)
        if concepts_match:
            concept_blocks = re.findall(
                r'\{\s*"id"[\s\S]*?\}\s*(?=,\s*\{|\s*\])', cleaned
            )
            parsed_c = []
            for block in concept_blocks:
                try:
                    b_clean = re.sub(r",\s*([\]}])", r"\1", block.strip())
                    parsed_c.append(json.loads(b_clean))
                except Exception:
                    continue
            if parsed_c:
                return {"concepts": parsed_c}

        if initial_err:
            raise initial_err
        raise ValueError("Impossibile analizzare l'output JSON restituito dall'LLM.")

    @classmethod
    def extract_with_llm(
        cls,
        chunks: list[DocumentChunk],
        model: str = "gemini-3.8-flash",
        api_key: str | None = None,
        timeout_seconds: float = 90.0,
    ) -> tuple[list[ConceptNode], list[ConceptRelation], list[CausalChain]]:
        """Extracts deep semantic ontology, ideal reference answers, and questions using Gemini."""
        key = api_key or os.getenv("GOOGLE_API_KEY", "")
        if not key:
            raise ValueError(
                "GOOGLE_API_KEY mancante. Configura la chiave API per procedere con l'analisi IA del documento."
            )

        try:
            from google import genai
            from google.genai import types

            client = genai.Client(api_key=key)

            # Cap chunks to avoid sending excessively large prompt payloads
            selected_chunks = chunks[:25] if len(chunks) > 25 else chunks
            full_text = "\n\n".join(
                f"### {c.section_title}\n{c.text}"
                for c in selected_chunks
                if len(c.text.split()) > 5
            )

            # Truncate text if it exceeds 30,000 characters to keep latency under a few seconds
            if len(full_text) > 30000:
                full_text = (
                    full_text[:30000] + "\n...[materiale didattico sintetizzato]..."
                )

            prompt = f"""Sei un professore universitario titolare del corso. Analizza il materiale didattico estratto ed estrai una sequenza organica, coerente e non ridondante di concetti fondamentali (da 3 a 7 concetti) per un esame orale universitario.

Per ciascun concetto fornisci:
- "id": identificativo univoco snake_case (es. "transazioni_base_eventual_consistency")
- "name": nome formale accademico in italiano (es. "Transazioni BASE ed Eventual Consistency")
- "summary": sintesi chiara ed elegante di 2-3 frasi che definisce il concetto
- "ideal_answer": la risposta teorica perfetta, rigorosa ed esaustiva che lo studente dovrebbe esporre all'esame
- "expected_key_points": elenco di 2-4 requisiti concettuali imprescindibili
- "main_question": domanda aperta posta dal docente
- "narrowing_questions": lista di 1 domanda di approfondimento su meccanismi specifici
- "scaffolding_hints": lista di 1 suggerimento guida per aiutare lo studente in difficoltà senza svelare la soluzione
- "stress_test_questions": lista di 1 domanda applicativa su scenari reali
- "collision_check_questions": lista di 1 domanda discriminativa rispetto a nozioni opposte
- "difficulty": "EASY" (nozioni introduttive senza prerequisiti), "MEDIUM" (concetti centrali con 1 prerequisito), "HARD" (teoremi o modelli avanzati con 2+ prerequisiti)
- "prerequisites": lista di concept_id propedeutici da conoscere prima di questo
- "contrasts_with": lista di concept_id di concetti opposti o complementari
- "causal_targets": lista di concept_id collegati da relazioni causa-effetto

Restituisci ESCLUSIVAMENTE un JSON valido con questa struttura:
{{
  "concepts": [
    {{
      "id": "string",
      "name": "string",
      "summary": "string",
      "ideal_answer": "string",
      "expected_key_points": ["string"],
      "main_question": "string",
      "narrowing_questions": ["string"],
      "scaffolding_hints": ["string"],
      "stress_test_questions": ["string"],
      "collision_check_questions": ["string"],
      "difficulty": "EASY|MEDIUM|HARD",
      "prerequisites": ["string"],
      "contrasts_with": ["string"],
      "causal_targets": ["string"]
    }}
  ]
}}

MATERIALE DIDATTICO:
{full_text}
"""

            def _call_gemini() -> str:
                candidate_models = [model]
                for fb in [
                    "gemini-3.8-flash",
                    "gemini-3.6-flash",
                    "gemini-3.5-flash",
                    "gemini-3-flash-preview",
                    "gemini-3.5-flash-lite",
                ]:
                    if fb not in candidate_models:
                        candidate_models.append(fb)

                last_error: Exception | None = None
                for candidate in candidate_models:
                    try:
                        logger.info("Tentativo di estrazione concetti con modello '%s'...", candidate)
                        response = client.models.generate_content(
                            model=candidate,
                            contents=prompt,
                            config=types.GenerateContentConfig(
                                response_mime_type="application/json",
                                temperature=0.2,
                                automatic_function_calling=types.AutomaticFunctionCallingConfig(
                                    disable=True
                                ),
                            ),
                        )
                        if response and response.text:
                            return response.text
                    except Exception as err:
                        logger.warning(
                            "generate_content con modello '%s' fallito: %s",
                            candidate,
                            err,
                        )
                        last_error = err

                if last_error:
                    raise last_error
                raise RuntimeError("Nessuna risposta valida ricevuta dai modelli Gemini.")

            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
                future = executor.submit(_call_gemini)
                response_text = future.result(timeout=timeout_seconds)

            parsed_data = cls._clean_and_parse_json(
                response_text, client=client, model=model
            )

            concepts: list[ConceptNode] = []
            relations: list[ConceptRelation] = []
            causal_chains: list[CausalChain] = []

            for c in parsed_data.get("concepts", []):
                cid = c.get("id") or re.sub(
                    r"\W+", "_", c.get("name", "").lower()
                ).strip("_")
                node = ConceptNode(
                    id=cid,
                    name=c.get("name", cid),
                    summary=c.get("summary", ""),
                    prerequisites=c.get("prerequisites", []),
                    contrasts_with=c.get("contrasts_with", []),
                    status=ConceptStatus.UNTESTED,
                    mastery_score=0.50,
                    properties={
                        "ideal_answer": c.get("ideal_answer", ""),
                        "expected_key_points": c.get("expected_key_points", []),
                        "main_question": c.get("main_question", ""),
                        "narrowing_questions": c.get("narrowing_questions", []),
                        "scaffolding_hints": c.get("scaffolding_hints", []),
                        "stress_test_questions": c.get("stress_test_questions", []),
                        "collision_check_questions": c.get(
                            "collision_check_questions", []
                        ),
                        "difficulty": c.get("difficulty", "MEDIUM"),
                        "causal_targets": c.get("causal_targets", []),
                    },
                )
                concepts.append(node)

                for prereq in node.prerequisites:
                    relations.append(
                        ConceptRelation(
                            source_id=node.id,
                            target_id=prereq,
                            rel_type=RelationType.REQUIRES,
                        )
                    )
                for contrast in node.contrasts_with:
                    relations.append(
                        ConceptRelation(
                            source_id=node.id,
                            target_id=contrast,
                            rel_type=RelationType.CONTRASTS_WITH,
                        )
                    )
                for ctarget in c.get("causal_targets", []):
                    relations.append(
                        ConceptRelation(
                            source_id=node.id,
                            target_id=ctarget,
                            rel_type=RelationType.CAUSES,
                        )
                    )
                    causal_chains.append(CausalChain(cause=node.id, effect=ctarget))

            logger.info(
                "Successfully extracted %d concepts with LLM model '%s'",
                len(concepts),
                model,
            )
            return concepts, relations, causal_chains

        except Exception as exc:
            logger.error(
                "LLM extraction failed (%s: %s).",
                model,
                exc,
            )
            raise RuntimeError(
                f"Errore durante l'analisi del documento con Gemini ({model}): {exc}"
            ) from exc

    @classmethod
    def extract_from_topic(
        cls,
        topic: str,
        model: str = "gemini-3.8-flash",
        api_key: str | None = None,
        timeout_seconds: float = 90.0,
    ) -> dict[str, Any]:
        """Generates an academic curriculum, study summary, and structured examination ontology from a topic prompt."""
        key = api_key or os.getenv("GOOGLE_API_KEY", "")
        if not key:
            raise ValueError(
                "GOOGLE_API_KEY mancante. Configura la chiave API per procedere con la generazione IA dell'esame."
            )

        try:
            from google import genai
            from google.genai import types

            client = genai.Client(api_key=key)

            prompt = f"""Sei un professore universitario titolare del corso. Lo studente desidera sostenere un esame orale interamente generato dall'IA sul seguente argomento/materia:
ARGOMENTO: {topic}

Progetta:
1. "course_title": un titolo accademico formale e chiaro per il corso/esame (es. "Diritto Costituzionale: Il Procedimento Legislativo").
2. "course_summary_markdown": un testo didattico di sintesi accademica strutturato in Markdown con sezioni (# Titolo, ## Capitolo 1...) che tratti in modo rigoroso ciascuno dei concetti previsti nell'esame (circa 300-600 parole).
3. "concepts": una sequenza organica, coerente e propedeutica di concetti fondamentali (da 4 a 6 concetti) per l'interrogazione orale.

Per ciascun concetto fornisci:
- "id": identificativo univoco snake_case (es. "bicameralismo_perfetto")
- "name": nome formale accademico in italiano (es. "Bicameralismo Perfetto e Funzioni Parlamentari")
- "summary": sintesi chiara di 2-3 frasi che definisce il concetto
- "ideal_answer": la risposta teorica perfetta, rigorosa ed esaustiva che lo studente dovrebbe esporre all'esame
- "expected_key_points": elenco di 2-4 requisiti concettuali imprescindibili
- "main_question": domanda aperta posta dal docente per avviare il colloquio
- "narrowing_questions": lista di 1 domanda di approfondimento su aspetti specifici o eccezioni
- "scaffolding_hints": lista di 1 suggerimento guida per aiutare lo studente in difficoltà senza svelare la soluzione
- "stress_test_questions": lista di 1 domanda applicativa su casi pratici o scenari reali
- "collision_check_questions": lista di 1 domanda discriminativa rispetto a nozioni correlate o opposte
- "difficulty": "EASY" (nozioni introduttive), "MEDIUM" (concetti centrali con 1 prerequisito), "HARD" (teoremi, casi complessi con 2+ prerequisiti)
- "prerequisites": lista di concept_id propedeutici da conoscere prima di questo
- "contrasts_with": lista di concept_id di concetti opposti o complementari
- "causal_targets": lista di concept_id collegati da relazioni causa-effetto

Restituisci ESCLUSIVAMENTE un JSON valido con questa struttura:
{{
  "course_title": "string",
  "course_summary_markdown": "string",
  "concepts": [
    {{
      "id": "string",
      "name": "string",
      "summary": "string",
      "ideal_answer": "string",
      "expected_key_points": ["string"],
      "main_question": "string",
      "narrowing_questions": ["string"],
      "scaffolding_hints": ["string"],
      "stress_test_questions": ["string"],
      "collision_check_questions": ["string"],
      "difficulty": "EASY|MEDIUM|HARD",
      "prerequisites": ["string"],
      "contrasts_with": ["string"],
      "causal_targets": ["string"]
    }}
  ]
}}
"""

            def _call_gemini() -> str:
                candidate_models = [model]
                for fb in [
                    "gemini-3.8-flash",
                    "gemini-3.6-flash",
                    "gemini-3.5-flash",
                    "gemini-3-flash-preview",
                    "gemini-3.5-flash-lite",
                ]:
                    if fb not in candidate_models:
                        candidate_models.append(fb)

                last_error: Exception | None = None
                for candidate in candidate_models:
                    try:
                        logger.info("Tentativo di generazione esame da argomento con modello '%s'...", candidate)
                        response = client.models.generate_content(
                            model=candidate,
                            contents=prompt,
                            config=types.GenerateContentConfig(
                                response_mime_type="application/json",
                                temperature=0.3,
                                automatic_function_calling=types.AutomaticFunctionCallingConfig(
                                    disable=True
                                ),
                            ),
                        )
                        if response and response.text:
                            return response.text
                    except Exception as err:
                        logger.warning(
                            "generate_content from topic con modello '%s' fallito: %s",
                            candidate,
                            err,
                        )
                        last_error = err

                if last_error:
                    raise last_error
                raise RuntimeError("Nessuna risposta valida ricevuta dai modelli Gemini.")

            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
                future = executor.submit(_call_gemini)
                response_text = future.result(timeout=timeout_seconds)

            parsed_data = cls._clean_and_parse_json(
                response_text, client=client, model=model
            )
            return parsed_data

        except Exception as exc:
            logger.error(
                "LLM topic generation failed (%s: %s).",
                model,
                exc,
            )
            raise RuntimeError(
                f"Errore durante la generazione dell'esame da argomento con Gemini: {exc}"
            ) from exc
