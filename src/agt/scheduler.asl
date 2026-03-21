/*******************************************************************************
 * SCHEDULER - Agente Planificador y Coordinador de Tareas
 *
 * Universidad de Vigo - Sistemas Inteligentes
 * Curso 2025-2026
 *
 * DISEÑO E IMPLEMENTACIÓN:
 *
 *   El scheduler actúa como cerebro central del sistema. Cuando el entorno
 *   genera un contenedor, notifica a TODOS los agentes con new_container(CId).
 *   El scheduler intercepta esa notificación, solicita información del
 *   contenedor al entorno (get_container_info), lo clasifica por prioridad
 *   y selecciona el robot más adecuado para transportarlo.
 *
 *   DECISIÓN 1 - Asignación directa con .send:
 *     En lugar de dejar que los robots soliciten tareas por su cuenta
 *     (request_task al Java), el scheduler asigna activamente usando
 *     .send(Robot, tell, task(CId, ShelfId)). Esto da al scheduler
 *     control total sobre qué robot recibe qué tarea.
 *
 *   DECISIÓN 2 - Sistema de prioridades (1=urgente > 2=frágil > 3=estándar):
 *     Los contenedores urgentes deben procesarse primero. Se implementa
 *     con planes ordenados: Jason prueba el primer plan aplicable para
 *     !try_assign_pending, de mayor a menor prioridad.
 *
 *   DECISIÓN 3 - Selección "best-fit" (robot más pequeño capaz):
 *     Para cada contenedor, se elige el robot más pequeño que pueda
 *     manejarlo. Así se preserve el robot_heavy (escaso y lento) para
 *     cargas grandes que solo él puede transportar.
 *     Orden de preferencia: robot_light → robot_medium → robot_heavy.
 *
 *   DECISIÓN 4 - Monitorización periódica con askOne:
 *     Cada 5 segundos, el scheduler consulta el estado actual de cada
 *     robot (state(S)) usando .send(Robot, askOne, ...). Esto permite
 *     detectar si un robot volvió a estar idle y asignar tareas pendientes,
 *     y también detectar robots ocupados por request_task externo.
 *
 *   DECISIÓN 5 - Flujo asíncrono en dos pasos:
 *     Para asignar una tarea: se llama a get_free_shelf(CId) al entorno
 *     y se espera la percepción +free_shelf(CId, ShelfId). Solo entonces
 *     se envía la tarea al robot. La creencia temporal assigning(CId, Robot)
 *     mantiene el contexto entre ambos pasos.
 *
 ******************************************************************************/

/* ============================================================================
 * CREENCIAS INICIALES - Base de Conocimiento
 * ============================================================================ */

/* Capacidades de los robots - deben coincidir exactamente con warehouse.mas2j
 * Formato: robot_capacity(Nombre, PesoMax, AnchoMax, AltoMax, Velocidad) */
robot_capacity(robot_light,  10, 1, 1, 3).
robot_capacity(robot_medium, 30, 1, 2, 2).
robot_capacity(robot_heavy, 100, 2, 3, 1).

/* Disponibilidad de robots: todos disponibles al inicio */
robot_available(robot_light).
robot_available(robot_medium).
robot_available(robot_heavy).

/* Estadísticas */
tasks_assigned(0).
containers_received(0).

/* ============================================================================
 * INICIO DEL AGENTE
 * ============================================================================ */

!start.

+!start : true <-
    .print("[SCHEDULER] Iniciado. Sistema listo para coordinar tareas.");
    !monitor_robots.   // Lanzar el bucle de monitorización de robots

/* ============================================================================
 * BUCLE DE MONITORIZACIÓN DE ROBOTS
 *
 * Cada 5 segundos consulta el estado de cada robot con askOne.
 * askOne es un tipo de mensaje Jason que consulta la base de creencias del
 * robot receptor SIN modificarla: .send(Robot, askOne, state(S), S) devuelve
 * en S el valor actual de state(X) en ese robot.
 *
 * Se manejan dos casos para cada robot:
 *   a) Robot marcado como OCUPADO por el scheduler pero volvió a idle
 *      → restaurar disponibilidad e intentar asignar tareas pendientes.
 *   b) Robot marcado como DISPONIBLE pero está ocupado (cogió tarea por
 *      request_task externo) → marcarlo como no disponible para sincronizar.
 * ============================================================================ */

+!monitor_robots : true <-
    .wait(5000);
    !check_robot_state(robot_light);
    !check_robot_state(robot_medium);
    !check_robot_state(robot_heavy);
    !monitor_robots.   // Bucle infinito

// Caso a: robot marcado como OCUPADO → comprobar si ya terminó
+!check_robot_state(Robot) : not robot_available(Robot) <-
    .send(Robot, askOne, state(S), S);
    if (S == idle) {
        .print("[SCHEDULER] ", Robot, " ha terminado su tarea. Ya disponible.");
        +robot_available(Robot);
        !try_assign_pending
    }.

// Caso b: robot marcado como DISPONIBLE → comprobar si está ocupado externamente
+!check_robot_state(Robot) : robot_available(Robot) <-
    .send(Robot, askOne, state(S), S);
    if (S \== idle) {
        .print("[SCHEDULER] ", Robot, " está ocupado por tarea externa. Sincronizando.");
        -robot_available(Robot)
    }.

/* ============================================================================
 * RECEPCIÓN DE NUEVO CONTENEDOR
 *
 * El Java hace addPercept SIN nombre de agente → percepción global recibida
 * por TODOS los agentes. El scheduler reacciona pidiendo info al entorno.
 * ============================================================================ */

+new_container(CId) : true <-
    ?containers_received(N);
    N1 is N + 1;
    -containers_received(N);
    +containers_received(N1);
    .print("[SCHEDULER] Nuevo contenedor detectado: ", CId, " (total recibidos: ", N1, ")");
    get_container_info(CId).   // Solicitar detalles al entorno Java

/* ============================================================================
 * CLASIFICACIÓN DEL CONTENEDOR
 *
 * Al recibir container_info del entorno, determinamos su prioridad y lo
 * añadimos a la cola interna como pending_task(Prioridad, CId, W, H, Peso, Tipo).
 * Inmediatamente intentamos asignarlo si hay robot disponible.
 *
 * Eliminamos la percepción del belief base tras procesarla para evitar que
 * container_info de otros contenedores se acumule y cause confusión.
 * ============================================================================ */

+container_info(CId, W, H, Weight, Type) : true <-
    -container_info(CId, W, H, Weight, Type);   // Limpiar percepción procesada
    !get_priority(Type, Priority);
    .print("[SCHEDULER] Clasificado ", CId,
           " | peso=", Weight, "kg | tam=", W, "x", H,
           " | tipo=", Type, " | prioridad=", Priority);
    +pending_task(Priority, CId, W, H, Weight, Type);
    !try_assign_pending.

/* Plan auxiliar: devuelve la prioridad según el tipo de contenedor.
 * DECISIÓN: urgent tiene prioridad máxima (1), fragile media (2), standard baja (3).
 * Se usa ordenación de planes de Jason: el primer plan con cabeza que unifique gana. */
+!get_priority("urgent",   1) <- true.
+!get_priority("fragile",  2) <- true.
+!get_priority(_,          3) <- true.   // Cualquier otro tipo → estándar

/* ============================================================================
 * INTENTO DE ASIGNACIÓN DE TAREA
 *
 * DECISIÓN: usamos tres planes ordenados por prioridad en la cabeza.
 * Jason selecciona el PRIMER plan cuyo contexto sea verdadero. Como los
 * planes se definen de mayor a menor prioridad, los urgentes siempre se
 * intentan asignar antes que los estándar, sin necesidad de ordenar una lista.
 * ============================================================================ */

// Prioridad 1: contenedores URGENTES primero
+!try_assign_pending : pending_task(1, CId, W, H, Weight, Type) <-
    .print("[SCHEDULER] >>> URGENTE en cola: ", CId, ". Intentando asignar...");
    !assign_container(1, CId, W, H, Weight, Type).

// Prioridad 2: contenedores FRAGILES segundo
+!try_assign_pending : pending_task(2, CId, W, H, Weight, Type) <-
    .print("[SCHEDULER] >>> FRAGIL en cola: ", CId, ". Intentando asignar...");
    !assign_container(2, CId, W, H, Weight, Type).

// Prioridad 3: contenedores ESTÁNDAR
+!try_assign_pending : pending_task(3, CId, W, H, Weight, Type) <-
    .print("[SCHEDULER] >>> Estandar en cola: ", CId, ". Intentando asignar...");
    !assign_container(3, CId, W, H, Weight, Type).

// Sin tareas pendientes: nada que hacer
+!try_assign_pending : true <-
    .print("[SCHEDULER] No hay tareas pendientes en cola.").

/* ============================================================================
 * ASIGNACIÓN: seleccionar el mejor robot y buscar estantería libre
 *
 * Dos pasos:
 *   1. Encontrar el mejor robot disponible → !find_best_robot
 *   2. Si hay robot: pedimos estantería al entorno con get_free_shelf(CId)
 *      La percepción +free_shelf(CId, ShelfId) se procesará en otro plan.
 *      Guardamos assigning(CId, Robot) como "estado temporal" entre ambos pasos.
 * ============================================================================ */

+!assign_container(Priority, CId, W, H, Weight, Type) <-
    !find_best_robot(W, H, Weight, Robot);
    if (Robot \== none) {
        // Verificar que el robot está realmente en state(idle) antes de asignarle
        // Esto evita perder tareas cuando el robot está en test_movement o busy
        .send(Robot, askOne, state(S), S);
        if (S == idle) {
            // Robot confirmado como idle: reservar y buscar estantería
            -robot_available(Robot);
            -pending_task(Priority, CId, W, H, Weight, Type);
            +assigning(CId, Robot);   // Estado temporal: esperando respuesta de get_free_shelf
            .print("[SCHEDULER] Robot seleccionado: ", Robot, " para ", CId, ". Buscando estanteria libre...");
            get_free_shelf(CId)       // Solicitar estantería apropiada al entorno Java
        } else {
            // Robot está ocupado (testing, moving, etc.) → sincronizar y dejar en cola
            .print("[SCHEDULER] ", Robot, " seleccionado pero en estado '", S, "'. Tarea ", CId, " queda en cola.");
            -robot_available(Robot)   // Sincronizar: marcarlo como no disponible
        }
    } else {
        .print("[SCHEDULER] Sin robots disponibles para ", CId, " (", Weight, "kg, ", W, "x", H, "). Queda en cola.")
    }.

// Plan de fallo: si get_free_shelf falla, restauramos el estado
-!assign_container(Priority, CId, W, H, Weight, Type) <-
    .print("[SCHEDULER] FALLO al asignar ", CId, ". Restaurando estado.");
    if (assigning(CId, Robot)) {
        -assigning(CId, Robot);
        +robot_available(Robot)
    };
    +pending_task(Priority, CId, W, H, Weight, Type).

/* ============================================================================
 * SELECCIÓN DEL MEJOR ROBOT - Estrategia "Best-Fit"
 *
 * DECISIÓN: elegimos el robot más pequeño que pueda manejar el contenedor.
 * Esto preserva robot_heavy (lento y escaso) para las cargas más grandes
 * que solo él puede transportar. La ordenación de planes garantiza que
 * robot_light se intenta primero, luego medium, luego heavy.
 *
 * La capacidad se verifica contra:
 *   - robot_light:  peso ≤ 10kg, tamaño ≤ 1×1
 *   - robot_medium: peso ≤ 30kg, tamaño ≤ 1×2 (W≤1, H≤2)
 *   - robot_heavy:  peso ≤ 100kg, tamaño ≤ 2×3
 * ============================================================================ */

// Robot light: el más rápido, pero solo carga pequeña
+!find_best_robot(W, H, Weight, robot_light) :
    robot_available(robot_light) &
    Weight <= 10 & W <= 1 & H <= 1
    <- true.

// Robot medium: intermedio - puede con 1×2 hasta 30kg
+!find_best_robot(W, H, Weight, robot_medium) :
    robot_available(robot_medium) &
    Weight <= 30 & W <= 1 & H <= 2
    <- true.

// Robot heavy: el más lento pero el único que puede con cargas 2×2, 2×3 o >30kg
+!find_best_robot(W, H, Weight, robot_heavy) :
    robot_available(robot_heavy) &
    Weight <= 100 & W <= 2 & H <= 3
    <- true.

// Ningún robot disponible o capaz en este momento
+!find_best_robot(W, H, Weight, none) : true <- true.

/* ============================================================================
 * RECEPCIÓN DE ESTANTERÍA LIBRE → ENVIAR TAREA AL ROBOT
 *
 * Cuando el entorno responde a get_free_shelf(CId) con la percepción
 * free_shelf(CId, ShelfId), enviamos la tarea al robot elegido usando
 * .send(Robot, tell, task(CId, ShelfId)).
 *
 * El mensaje "tell" añade task(CId, ShelfId) a la base de creencias
 * del robot receptor, disparando su plan +task(CId, ShelfId).
 *
 * Tras asignar, intentamos asignar la siguiente tarea pendiente.
 * ============================================================================ */

+free_shelf(CId, ShelfId) : assigning(CId, Robot) <-
    -free_shelf(CId, ShelfId);   // Limpiar percepción procesada
    -assigning(CId, Robot);
    // Enviar tarea al robot directamente via mensaje
    .send(Robot, tell, task(CId, ShelfId));
    // Actualizar estadísticas
    ?tasks_assigned(N);
    N1 is N + 1;
    -tasks_assigned(N);
    +tasks_assigned(N1);
    .print("[SCHEDULER] *** TAREA ASIGNADA: ", CId,
           " → ", Robot, " → estanteria ", ShelfId,
           " | Total asignadas: ", N1, " ***");
    !try_assign_pending.   // Intentar asignar la siguiente tarea en cola

// free_shelf sin assigning activo (caso inesperado)
+free_shelf(CId, ShelfId) : not assigning(CId, _) <-
    -free_shelf(CId, ShelfId);
    .print("[SCHEDULER] AVISO: free_shelf recibido sin asignacion activa para ", CId).

/* ============================================================================
 * MANEJO DE ERRORES DEL ENTORNO
 * ============================================================================ */

// Sin estanterías disponibles: liberar el robot y volver a encolar
+error(no_shelf_available, Data) : assigning(CId, Robot) <-
    .print("[SCHEDULER] Sin estanterias para ", CId, ". Liberando ", Robot, ".");
    -assigning(CId, Robot);
    +robot_available(Robot).

// Cualquier otro error
+error(ErrorType, Data) : true <-
    .print("[SCHEDULER] ERROR recibido: ", ErrorType, " | datos: ", Data).

