#!/usr/bin/env python3
"""Pruebas reproducibles del gemelo Prolog y del puente Janus."""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from gemelo_janus import (  # noqa: E402
    GemeloDigital,
    ApiError,
    janus,
    simular_caida_control,
    simular_perder_frio,
    snapshot_api,
    snapshot_demo,
)


class GemeloDigitalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gemelo = GemeloDigital()

    def setUp(self) -> None:
        self.snapshot = snapshot_demo()
        self.gemelo.sincronizar(self.snapshot)

    def test_snapshot_demo_fiel_a_p80_demo(self) -> None:
        informe = self.gemelo.informe()
        self.assertEqual(informe["total_lotes"], 12)
        self.assertEqual(informe["metricas"]["litros_producidos"], 2400)
        self.assertEqual(informe["metricas"]["litros_en_proceso"], 2850)
        self.assertEqual(informe["metricas"]["lotes_por_etapa"]["fermentacion"], 4)
        self.assertEqual(len(self.snapshot["fermentadores"]), 6)
        self.assertEqual(
            [f["capacidad_litros"] for f in self.snapshot["fermentadores"]],
            [2000, 1500, 1200, 1000, 800, 600],
        )

    def test_secuencia_estricta(self) -> None:
        self.assertEqual(
            self.gemelo.puede_avanzar(12, "coccion")["estado"], "permitido"
        )
        self.assertEqual(
            self.gemelo.puede_avanzar(12, "maduracion")["motivo"],
            "secuencia_invalida",
        )
        self.assertEqual(
            self.gemelo.puede_avanzar(1, "undefined")["motivo"], "lote_terminado"
        )

    def test_asignacion_y_capacidad(self) -> None:
        self.assertEqual(
            self.gemelo.puede_avanzar(10)["motivo"], "sin_fermentador_disponible"
        )

        libre = snapshot_demo()
        libre["fermentadores"][0]["lote_id"] = None
        libre["fermentadores"][0]["activo"] = False
        self.gemelo.sincronizar(libre)
        transicion = self.gemelo.puede_avanzar(10)
        self.assertEqual(transicion["estado"], "permitido")
        candidatos = janus.query_once(
            "cerveceria_gemelo:candidatos(Id, C)", {"Id": 10}
        )["C"]
        self.assertIn(1, candidatos)

        insuficiente = snapshot_demo()
        insuficiente["lotes"][9]["litros"] = 2500
        insuficiente["lotes"][9]["fermentador_id"] = 6
        self.gemelo.sincronizar(insuficiente)
        self.assertEqual(
            self.gemelo.puede_avanzar(10)["motivo"], "capacidad_insuficiente"
        )

        ocupado = snapshot_demo()
        ocupado["lotes"][9]["fermentador_id"] = 1
        self.gemelo.sincronizar(ocupado)
        self.assertEqual(
            self.gemelo.puede_avanzar(10)["motivo"], "fermentador_ocupado"
        )

    def test_liberacion_y_consistencia(self) -> None:
        transiciones = {
            t["lote_id"]: t for t in self.gemelo.informe()["transiciones"]
        }
        self.assertEqual(transiciones[8]["libera"], 5)

        inconsistente = snapshot_demo()
        inconsistente["lotes"][7]["etapa"] = "envasado"
        inconsistente["lotes"][7]["fermentador_id"] = 5
        self.gemelo.sincronizar(inconsistente)
        tipos = [h["tipo"] for h in self.gemelo.informe()["auditoria"]]
        self.assertIn("asignacion_activa_en_etapa_final", tipos)

    def test_riesgo_termico_y_normalizacion(self) -> None:
        caliente = simular_perder_frio(self.snapshot, 1, 5.0)
        self.gemelo.sincronizar(caliente)
        riesgos = self.gemelo.informe()["riesgos"]
        self.assertEqual(len(riesgos), 1)
        self.assertEqual(riesgos[0]["lote_id"], 4)
        causa = riesgos[0]["motivos"][0]
        self.assertEqual(causa["causa"], "desviacion_termica")
        self.assertEqual(causa["fermentador_id"], 1)
        self.assertEqual(causa["desviacion"], 5.0)
        self.assertEqual(self.gemelo.motivos(4)[0]["causa"], "desviacion_termica")

        self.gemelo.sincronizar(snapshot_demo())
        self.assertEqual(self.gemelo.informe()["riesgos"], [])
        normalizado = janus.query_once(
            "cerveceria_gemelo:estado_normal(Id)", {"Id": 4}
        )
        self.assertTrue(normalizado["truth"])

    def test_caida_del_control_de_temperatura(self) -> None:
        caido = simular_caida_control(snapshot_demo())
        self.gemelo.sincronizar(caido)
        informe = self.gemelo.informe()
        self.assertEqual(len(informe["riesgos"]), 6)
        self.assertTrue(
            all(
                any(
                    m["causa"] == "caida_control_temperatura"
                    for m in riesgo["motivos"]
                )
                for riesgo in informe["riesgos"]
            )
        )
        self.assertTrue(
            any(
                r["accion"] == "reiniciar_control_temperatura"
                for r in informe["recomendaciones"]
            )
        )

    def test_metricas_deducidas_vs_reportadas(self) -> None:
        self.assertEqual(self.gemelo.litros_producidos(), 2400)
        comparaciones = self.gemelo.informe()["comparacion_metricas"]
        self.assertTrue(all(c["coincide"] == "true" for c in comparaciones))

        alterado = snapshot_demo()
        alterado["metricas"]["litros_producidos"] = 999
        self.gemelo.sincronizar(alterado)
        por_clave = {
            c["clave"]: c for c in self.gemelo.informe()["comparacion_metricas"]
        }
        self.assertEqual(por_clave["litros_producidos"]["deducido"], 2400)
        self.assertEqual(por_clave["litros_producidos"]["reportado"], 999)
        self.assertEqual(por_clave["litros_producidos"]["coincide"], "false")

    def test_capacidad_disponible_y_alerta_inconsistente(self) -> None:
        self.assertEqual(self.gemelo.informe()["capacidad_disponible"], 0)

        libres = snapshot_demo()
        for fermentador in libres["fermentadores"]:
            fermentador["lote_id"] = None
            fermentador["activo"] = False
        self.gemelo.sincronizar(libres)
        self.assertEqual(self.gemelo.informe()["capacidad_disponible"], 7100)

        incoherente = snapshot_demo()
        incoherente["fermentadores"][0]["en_alerta"] = True
        self.gemelo.sincronizar(incoherente)
        tipos = [h["tipo"] for h in self.gemelo.informe()["auditoria"]]
        self.assertIn("alerta_temperatura_inconsistente", tipos)

    @unittest.skipUnless(os.getenv("P80_API_BASE"), "P80_API_BASE no configurado")
    def test_integracion_con_api_erlang(self) -> None:
        snapshot = snapshot_api(os.environ["P80_API_BASE"])
        self.gemelo.sincronizar(snapshot)
        self.assertGreater(self.gemelo.informe()["total_lotes"], 0)

    def test_api_apagada_levanta_error_claro(self) -> None:
        with self.assertRaises(ApiError):
            snapshot_api("http://127.0.0.1:1", timeout=0.2)


if __name__ == "__main__":
    unittest.main()
