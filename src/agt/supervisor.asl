/*******************************************************************************
 * SUPERVISOR - Agente de Monitorización y Gestión de Errores
 * 
 * Universidad de Vigo - Sistemas Inteligentes
 * Curso 2025-2026
 * 
 * RESPONSABILIDADES:
 *   1. Monitorizar el estado global del sistema
 *   2. Detectar anomalías y errores
 *   3. Coordinar recuperación de errores
 *   4. Mantener métricas de rendimiento
 *   5. Identificar cuellos de botella
 *   6. Generar reportes y análisis
 * 
 ******************************************************************************/

/* ============================================================================
 * CREENCIAS INICIALES
 * ============================================================================ */

/* Métricas del sistema */
total_errors(0).
errors_by_type(container_too_heavy, 0).
errors_by_type(container_too_big, 0).
errors_by_type(shelf_full, 0).
errors_by_type(illegal_move, 0).
errors_by_type(conflict, 0).
errors_by_type(route_blocked, 0).

/* Tiempos de inicio */
system_start_time(0).

/* Umbral de alerta */
max_errors_per_minute(10).
max_consecutive_errors(5).

/* Contador de contenedores recibidos */
total_containers_received(0).

/* ============================================================================
 * PLANES PRINCIPALES
 * ============================================================================ */

!start.

+!start : true <-
    .print("🛡️ [SUPERVISOR] Sistema de supervisión iniciado");
    !monitor_loop.

// Bucle periódico de reporte de estado (cada 30 segundos)
+!monitor_loop : true <-
    .wait(30000);
    ?total_containers_received(N);
    ?total_errors(E);
    .print("📊 [SUPERVISOR] Estado del sistema: ", N, " contenedores recibidos, ", E, " errores totales");
    !monitor_loop.

/* ============================================================================
 * REACCIÓN A EVENTOS
 * ============================================================================ */

// Registrar llegada de nuevo contenedor
+new_container(CId) : total_containers_received(N) <-
    N1 = N + 1;
    -+total_containers_received(N1);
    .print("🔍 [SUPERVISOR] Nuevo contenedor detectado #", N1, ": ", CId).

// Reaccionar a errores propios (errores generados por el supervisor mismo si existieran)
+error(ErrorType, Data) : total_errors(E) <-
    E1 = E + 1;
    -+total_errors(E1);
    .print("⚠️ [SUPERVISOR] Error registrado #", E1, ": ", ErrorType, " - ", Data).
