#!/usr/bin/env python3
"""Puente Python/Janus entre la API Erlang/OTP y el gemelo Prolog."""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

try:
    import janus_swi as janus
except ImportError:
    try:
        import janus as _janus

        janus = _janus
    except ImportError as exc:
        raise SystemExit(
            "Falta Janus. Instala SWI-Prolog >= 9.1.12 y ejecuta:\n"
            "  conda create -n p80-gemelo -c conda-forge python=3.13 "
            "swi-prolog c-compiler pip\n"
            "  conda run -n p80-gemelo python -m pip install janus-swi==1.5.3"
        ) from exc

BASE_DIR = Path(__file__).resolve().parent
KB_PATH = BASE_DIR / "cerveceria_gemelo.pl"
DEFAULT_API_BASE = "http://localhost:8080"

RECETAS_DEMO = [
    "IPA Tijuana",
    "Pale Ale Baja",
    "Stout Frontera",
    "Lager Pacifico",
    "Saison Valle",
]
VOLUMENES_DEMO = [1000, 800, 600, 500, 450, 400, 350, 300, 250, 220, 200, 180]
AVANCES_DEMO = {
    1: 5, 2: 5, 3: 5,
    4: 2, 5: 2, 6: 2, 7: 2,
    8: 3, 9: 3,
    10: 1, 11: 1,
    12: 0,
}
ETAPAS = [
    "molienda", "coccion", "fermentacion",
    "maduracion", "envasado", "terminado",
]
FERMENTADORES_DEMO = [
    ("Fermentador A", 2000, 20.0),
    ("Fermentador B", 1500, 19.0),
    ("Fermentador C", 1200, 18.0),
    ("Fermentador D", 1000, 12.0),
    ("Fermentador E", 800, 20.0),
    ("Fermentador F", 600, 18.0),
]
TS_BASE_DEMO = 1_794_200_000_000


class BridgeError(RuntimeError):
    pass


class ApiError(BridgeError):
    pass


def get_json(api_base: str, path: str, timeout: float = 5.0) -> dict[str, Any]:
    url = api_base.rstrip("/") + path
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            return json.loads(raw)
        except json.JSONDecodeError as inner:
            raise ApiError(f"HTTP {exc.code} en {url}: {raw[:200]}") from inner
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise ApiError(f"No se pudo conectar con {url}: {exc}") from exc
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ApiError(f"JSON inválido en {url}: {exc}") from exc


def snapshot_api(api_base: str, timeout: float = 5.0) -> dict[str, Any]:
    salud = get_json(api_base, "/health", timeout)
    lotes = get_json(api_base, "/api/lotes", timeout).get("lotes", [])
    fermentadores = get_json(api_base, "/api/fermentadores", timeout).get(
        "fermentadores", []
    )
    metricas = get_json(api_base, "/api/metricas", timeout).get("metricas", {})
    eventos = get_json(api_base, "/api/eventos?limite=200", timeout).get(
        "eventos", []
    )
    procesos = {
        str(proceso.get("nombre")): bool(proceso.get("vivo"))
        for proceso in salud.get("procesos", [])
    }
    return {
        "modo": "api",
        "salud": salud.get("estado", "desconocido"),
        "lotes": lotes,
        "fermentadores": fermentadores,
        "metricas": metricas,
        "eventos": eventos,
        "control_activo": procesos.get("p80_control_temperatura", True),
    }


def _etapa_demo(indice: int) -> str:
    return ETAPAS[min(AVANCES_DEMO[indice], len(ETAPAS) - 1)]


def _fermentador_demo(indice: int) -> int | None:
    if 4 <= indice <= 9:
        return indice - 3
    return None


def _historial_demo(etapa: str, ts: int) -> list[dict[str, Any]]:
    return [{
        "ts": ts,
        "tipo": "transicion",
        "etapa": etapa,
        "detalle": f"Etapa inicial del escenario: {etapa}",
    }]


def snapshot_demo() -> dict[str, Any]:
    lotes = []
    asignados = {}
    for indice, litros in enumerate(VOLUMENES_DEMO, start=1):
        receta = RECETAS_DEMO[(indice - 1) % len(RECETAS_DEMO)]
        etapa = _etapa_demo(indice)
        fermentador_id = _fermentador_demo(indice)
        if fermentador_id is not None:
            asignados[fermentador_id] = indice
        lotes.append({
            "id": indice,
            "nombre": f"{receta} #{indice}",
            "receta": receta,
            "litros": litros,
            "etapa": etapa,
            "fermentador_id": fermentador_id,
            "en_riesgo": False,
            "motivo_riesgo": None,
            "creado_en": TS_BASE_DEMO,
            "actualizado_en": TS_BASE_DEMO + indice * 1000,
            "historial": _historial_demo(etapa, TS_BASE_DEMO + indice * 1000),
        })

    fermentadores = []
    for indice, (nombre, capacidad, objetivo) in enumerate(FERMENTADORES_DEMO, start=1):
        lote_id = asignados.get(indice)
        fermentadores.append({
            "id": indice,
            "nombre": nombre,
            "capacidad_litros": capacidad,
            "temperatura_actual": objetivo,
            "temperatura_objetivo": objetivo,
            "tolerancia": 1.0,
            "lote_id": lote_id,
            "activo": lote_id is not None,
            "creado_en": TS_BASE_DEMO,
            "actualizado_en": TS_BASE_DEMO + indice,
            "desviacion": 0.0,
            "en_alerta": False,
        })

    return {
        "modo": "demo",
        "salud": "ok",
        "lotes": lotes,
        "fermentadores": fermentadores,
        "metricas": metricas_desde(lotes, fermentadores),
        "eventos": [],
        "control_activo": True,
    }


def metricas_desde(
    lotes: list[dict[str, Any]],
    fermentadores: list[dict[str, Any]],
) -> dict[str, Any]:
    por_etapa = {etapa: 0 for etapa in ETAPAS}
    for lote in lotes:
        etapa = str(lote.get("etapa"))
        if etapa in por_etapa:
            por_etapa[etapa] += 1
    return {
        "lotes_por_etapa": por_etapa,
        "total_lotes": len(lotes),
        "lotes_en_riesgo": sum(1 for lote in lotes if lote.get("en_riesgo")),
        "fermentadores_activos": sum(
            1 for fermentador in fermentadores if fermentador.get("lote_id") is not None
        ),
        "fermentadores_totales": len(fermentadores),
        "desviaciones_temperatura": sum(
            1 for fermentador in fermentadores if fermentador.get("en_alerta")
        ),
        "litros_producidos": sum(
            int(lote.get("litros", 0))
            for lote in lotes
            if lote.get("etapa") == "terminado"
        ),
        "litros_en_proceso": sum(
            int(lote.get("litros", 0))
            for lote in lotes
            if lote.get("etapa") != "terminado"
        ),
        "eventos_registrados": 0,
        "alertas_temperatura": 0,
        "caidas_control_temperatura": 0,
        "inicios_control_temperatura": 1,
    }


def _marcar_lote(lotes: list[dict[str, Any]], lote_id: Any, motivo: str) -> None:
    for lote in lotes:
        if lote.get("id") == lote_id:
            lote["en_riesgo"] = True
            lote["motivo_riesgo"] = motivo


def simular_perder_frio(
    snapshot: dict[str, Any], fermentador_id: int, grados: float
) -> dict[str, Any]:
    resultado = copy.deepcopy(snapshot)
    for fermentador in resultado.get("fermentadores", []):
        if fermentador.get("id") != fermentador_id:
            continue
        objetivo = float(fermentador["temperatura_objetivo"])
        actual = round(objetivo + float(grados), 2)
        desviacion = round(abs(actual - objetivo), 2)
        fermentador["temperatura_actual"] = actual
        fermentador["desviacion"] = desviacion
        fermentador["en_alerta"] = desviacion > float(fermentador["tolerancia"])
        _marcar_lote(
            resultado.get("lotes", []),
            fermentador.get("lote_id"),
            "Desviación térmica",
        )
        resultado.setdefault("eventos", []).insert(0, {
            "tipo": "alerta_temperatura",
            "ts": TS_BASE_DEMO,
            "datos": {
                "fermentador_id": fermentador_id,
                "temperatura_actual": actual,
                "temperatura_objetivo": objetivo,
                "desviacion": desviacion,
                "tolerancia": fermentador["tolerancia"],
                "lote_id": fermentador.get("lote_id"),
                "severidad": "alta",
            },
        })
        resultado["modo"] = "caos"
        resultado["metricas"] = metricas_desde(
            resultado.get("lotes", []), resultado.get("fermentadores", [])
        )
        return resultado
    raise BridgeError(f"Fermentador {fermentador_id} no existe en la instantánea")


def simular_caida_control(snapshot: dict[str, Any]) -> dict[str, Any]:
    resultado = copy.deepcopy(snapshot)
    resultado["control_activo"] = False
    resultado["modo"] = "caos"
    lotes_afectados = [
        fermentador.get("lote_id")
        for fermentador in resultado.get("fermentadores", [])
        if fermentador.get("lote_id") is not None
    ]
    for lote_id in lotes_afectados:
        _marcar_lote(
            resultado.get("lotes", []),
            lote_id,
            "Control de temperatura caído; lecturas no confiables",
        )
    resultado.setdefault("eventos", []).insert(0, {
        "tipo": "control_temperatura_caido",
        "ts": TS_BASE_DEMO,
        "datos": {"razon": "simulacion_janus", "severidad": "alta"},
    })
    resultado.setdefault("eventos", []).insert(0, {
        "tipo": "riesgo_por_fallo_control",
        "ts": TS_BASE_DEMO,
        "datos": {"motivo": "control_temperatura_caido", "lotes": lotes_afectados},
    })
    resultado["metricas"] = metricas_desde(
        resultado.get("lotes", []), resultado.get("fermentadores", [])
    )
    return resultado


class GemeloDigital:
    """Carga la base Prolog, sincroniza estado y ejecuta consultas estructuradas."""

    def __init__(self, kb_path: Path = KB_PATH) -> None:
        if not kb_path.exists():
            raise BridgeError(f"No existe la base de conocimiento: {kb_path}")
        janus.consult(str(kb_path))
        self.kb_path = kb_path

    def sincronizar(self, snapshot: dict[str, Any]) -> None:
        estado = {
            "lotes": snapshot.get("lotes", []),
            "fermentadores": snapshot.get("fermentadores", []),
            "metricas": snapshot.get("metricas", {}),
            "eventos": snapshot.get("eventos", []),
            "control_activo": bool(snapshot.get("control_activo", True)),
            "modo": snapshot.get("modo", "demo"),
        }
        respuesta = janus.query_once(
            "cerveceria_gemelo:sincronizar(Estado)", {"Estado": estado}
        )
        if not respuesta.get("truth"):
            raise BridgeError("sincronizar/1 falló en Prolog")

    def informe(self) -> dict[str, Any]:
        respuesta = janus.query_once("cerveceria_gemelo:informe(Informe)")
        if not respuesta.get("truth"):
            raise BridgeError("informe/1 falló en Prolog")
        return dict(respuesta["Informe"])

    def puede_avanzar(
        self, lote_id: int, destino: str | None = None
    ) -> dict[str, Any]:
        entradas: dict[str, Any] = {"Id": int(lote_id)}
        if destino is not None:
            entradas["Destino"] = destino
        respuesta = janus.query_once(
            "cerveceria_gemelo:puede_avanzar_info(Id, Destino, Info)", entradas
        )
        if not respuesta.get("truth"):
            raise BridgeError(f"Lote {lote_id} no existe en el gemelo")
        return dict(respuesta["Info"])

    def motivos(self, lote_id: int) -> list[dict[str, Any]]:
        respuesta = janus.query_once(
            "cerveceria_gemelo:motivos_dict(Id, Motivos)", {"Id": int(lote_id)}
        )
        if not respuesta.get("truth"):
            return []
        return list(respuesta["Motivos"])

    def litros_producidos(self) -> int:
        respuesta = janus.query_once(
            "cerveceria_gemelo:litros_producidos(Litros)"
        )
        if not respuesta.get("truth"):
            raise BridgeError("litros_producidos/1 falló en Prolog")
        return int(respuesta["Litros"])


def _motivo_texto(motivo: dict[str, Any]) -> str:
    causa = str(motivo.get("causa", "desconocida"))
    if causa == "desviacion_termica":
        return (
            f"desviacion_termica(fermentador={motivo.get('fermentador_id')}, "
            f"desviacion={motivo.get('desviacion')} °C)"
        )
    return causa


def imprimir_reporte(
    snapshot: dict[str, Any], informe: dict[str, Any], solo_json: bool = False
) -> None:
    if solo_json:
        print(json.dumps({"origen": snapshot.get("modo"), "informe": informe},
                         ensure_ascii=False, indent=2, default=str))
        return

    print(f"Modo del gemelo: {informe.get('modo')}")
    print(f"Lotes sincronizados: {informe.get('total_lotes')}")
    print(f"Salud Erlang: {snapshot.get('salud', 'no disponible')}")
    print(f"Control de temperatura: {snapshot.get('control_activo')}")

    print("\nRiesgos deducidos:")
    riesgos = informe.get("riesgos", [])
    if not riesgos:
        print("  ninguno")
    for riesgo in riesgos:
        motivos = ", ".join(_motivo_texto(m) for m in riesgo.get("motivos", []))
        print(
            f"  lote {riesgo.get('lote_id')} ({riesgo.get('etapa')}, "
            f"{riesgo.get('litros')} L): {motivos}"
        )

    print("\nTransiciones:")
    for transicion in informe.get("transiciones", []):
        candidatos = transicion.get("fermentadores_candidatos", [])
        extra = f"; candidatos={candidatos}" if candidatos else ""
        libera = transicion.get("libera")
        if libera not in (None, "undefined"):
            extra += f"; libera fermentador {libera}"
        print(
            f"  lote {transicion.get('lote_id')} -> "
            f"{transicion.get('destino')}: {transicion.get('estado')}"
            f"[{transicion.get('motivo')}]{extra}"
        )

    print("\nRecomendaciones:")
    recomendaciones = informe.get("recomendaciones", [])
    if not recomendaciones:
        print("  ninguna")
    for recomendacion in recomendaciones:
        print(
            f"  [{recomendacion.get('prioridad')}] "
            f"{recomendacion.get('accion')}: "
            f"{json.dumps(recomendacion, ensure_ascii=False, default=str)}"
        )

    print("\nAuditoría:")
    hallazgos = informe.get("auditoria", [])
    if not hallazgos:
        print("  consistente")
    for hallazgo in hallazgos:
        print(f"  {json.dumps(hallazgo, ensure_ascii=False, default=str)}")

    print("\nMétricas deducidas vs reportadas:")
    for comparacion in informe.get("comparacion_metricas", []):
        marca = "OK" if comparacion.get("coincide") == "true" else "DIFIERE"
        print(
            f"  {comparacion.get('clave')}: deducido="
            f"{comparacion.get('deducido')}, reportado="
            f"{comparacion.get('reportado')} [{marca}]"
        )
    print(f"Capacidad disponible: {informe.get('capacidad_disponible')} L")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Reporte del Gemelo Digital cervecero con Prolog + Janus"
    )
    parser.add_argument("--mode", choices=["api", "demo", "caos"], default="api")
    parser.add_argument(
        "--api-base", default=os.getenv("P80_API_BASE", DEFAULT_API_BASE)
    )
    parser.add_argument("--fermentador", type=int, default=1)
    parser.add_argument("--grados", type=float, default=5.0)
    parser.add_argument("--drop-control", action="store_true")
    parser.add_argument("--simular-frio", action="store_true")
    parser.add_argument("--fallback-demo", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--timeout", type=float, default=5.0)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.mode == "api":
            try:
                snapshot = snapshot_api(args.api_base, args.timeout)
            except ApiError as exc:
                if not args.fallback_demo:
                    raise
                print(f"Aviso: {exc}. Usando escenario demo local.", file=sys.stderr)
                snapshot = snapshot_demo()
            if args.simular_frio:
                snapshot = simular_perder_frio(
                    snapshot, args.fermentador, args.grados
                )
            if args.drop_control:
                snapshot = simular_caida_control(snapshot)
        elif args.mode == "demo":
            snapshot = snapshot_demo()
            if args.simular_frio:
                snapshot = simular_perder_frio(
                    snapshot, args.fermentador, args.grados
                )
            if args.drop_control:
                snapshot = simular_caida_control(snapshot)
        else:
            snapshot = simular_perder_frio(
                snapshot_demo(), args.fermentador, args.grados
            )
            if args.drop_control:
                snapshot = simular_caida_control(snapshot)

        gemelo = GemeloDigital()
        gemelo.sincronizar(snapshot)
        informe = gemelo.informe()
        imprimir_reporte(snapshot, informe, args.json)
        return 0
    except BridgeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
