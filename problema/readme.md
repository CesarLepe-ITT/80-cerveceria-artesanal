# #80 — Cervecería artesanal: el problema

## Contexto
Tijuana es de las ciudades con mayor escena de cerveza artesanal en Mexico, con decenas de cervecerias que producen lotes pequeños y muchas recetas. Cada lote pasa por etapas con tiempos y temperaturas estrictos, y los fermentadores son pocos, asi que la planeacion de equipo es todo.

## Datos del mundo real
- Etapas: molienda → **maceracion** (~65-68 °C por ~60 min) → filtrado → **coccion** (60-90 min, con lupulo) → enfriado → **fermentacion** → maduracion → carbonatacion → embotellado/barril.
- Fermentacion: ales 18-22 °C por 7-14 dias; lagers 8-12 °C por 2-4 semanas; una temperatura equivocada da sabores no deseados o detiene la fermentacion.
- Se mide **densidad**: la original (OG, antes de fermentar) y la final (FG); el alcohol se estima como (OG − FG) × 131.25. Ejemplo: OG 1.052 y FG 1.010 dan ≈ 5.5 % de alcohol. La fermentacion termina cuando la densidad se estabiliza por 2-3 dias.
- Una cerveceria artesanal tiene lotes de 200-2,000 litros y 3-8 fermentadores; un fermentador ocupado por un lote no puede usarse para otro hasta limpiarse y sanitizarse (horas).
- Contaminacion, falta de limpieza o una fermentacion atorada echan a perder todo un lote.
- Cada lote requiere trazabilidad de insumos (malta, lupulo, levadura por lote del proveedor) y registro para etiquetado y cumplimiento sanitario.

## El problema
Planear y llevar el seguimiento de lotes de produccion a traves de sus etapas, asignar fermentadores y equipo sin conflictos, controlar la temperatura y la densidad de cada fermentador, avisar cuando una etapa debe terminar o algo se desvia, y mantener la historia de cada lote y de los insumos usados.

## Escenario a simular
- 5 recetas, 6 fermentadores, 12 lotes en un mes.
- Un fermentador que pierde frio y sube 5 °C en una noche.
- Un lote cuya densidad no baja y su fermentador esta reservado para el siguiente.

## Casos dificiles
- Reprogramar el calendario cuando un lote se retrasa.
- Un lote que se divide en dos fermentadores.
- Retirar un lote por un insumo contaminado y rastrear que mas lo uso.

## Preguntas guia
1. ¿Que determina que una etapa "termino" y quien lo confirma?
2. ¿Como evitas que un retraso desbarate todo el calendario?

## Que debes entregar (sin que aqui se de la solucion)
- Un diseño OTP explicado brevemente: procesos, supervisores y quien reinicia a quien, justificando cada decision frente a los casos dificiles de arriba.
- La simulacion del escenario descrito, con datos generados y fallas inyectadas.
- Una lista de supuestos propios y de las cifras de este documento que verificaste.
- Una prueba de caos: que mataste, que esperabas y que ocurrio.
- `rebar3 compile` y `rebar3 eunit` en verde; capturas de Stitch y de la app real si hay interfaz.

---
*Las cifras son de referencia (ordenes de magnitud). Verifica la fuente vigente antes de citarlas en tu entrega y anota las que uses en tu README.*
