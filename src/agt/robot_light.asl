/*******************************************************************************
 * ROBOT LIGERO - Sistema de Gestión Logística de Almacén
 * 
 * Universidad de Vigo - Sistemas Inteligentes
 * Curso 2025-2026
 * 
 * CAPACIDADES:
 *   - Peso máximo: 10 kg
 *   - Tamaño máximo: 1×1
 *   - Velocidad: Alta (3)
 * 
 ******************************************************************************/

/* ============================================================================
 * CREENCIAS INICIALES
 * ============================================================================
 * Las creencias iniciales se proporcionan desde el archivo .mas2j
 * - robot_type(light): tipo de robot
 * - max_weight(10): peso máximo que puede cargar
 * - max_size(1,1): tamaño máximo de contenedor
 */

/* Estado inicial del robot */
state(idle).         // Estados posibles: idle, moving, picking, carrying, dropping
position(1,3).       // Posición inicial
carrying(none).      // Contenedor que está cargando

/* ============================================================================
 * PLANES PRINCIPALES
 * ============================================================================ */

!start.

// Plan inicial: Arrancar el robot y hacer pruebas de movimiento
+!start : true <-
    .print("Robot ligero iniciado - Capacidad: 10kg, 1x1");
    //.print("Iniciando secuencia de prueba de movimientos...");
    //-+state(testing);
    //!test_movement;
    !work_cycle.

// Secuencia de prueba de movimientos
+!test_movement : true <-
    .print("Posición inicial: (1,3)");
    .wait(1000);
    
    .print("Movimiento 1: Ir al área de entrada (1,1)");
    move_to(1, 1);
    .wait(2000);
    
    .print("Movimiento 2: Ir al área de clasificación (5,1)");
    move_to(5, 1);
    .wait(2000);
    
    .print("Movimiento 3: Ir a zona de estanterías pequeñas (12,3)");
    move_to(12, 3);
    .wait(2000);
    
    .print("Movimiento 4: Explorar más estanterías (16,3)");
    move_to(16, 3);
    .wait(2000);
    
    .print("Movimiento 5: Volver a posición intermedia (8,5)");
    move_to(8, 5);
    .wait(2000);
    
    .print("Prueba de movimientos completada. Robot funcionando correctamente.");
    -+state(idle).

// Ciclo de trabajo principal
+!work_cycle : state(idle) <-
    .print("[LIGHT] Solicitando nueva tarea...");
    request_task;
    .wait(3000);  // Esperar 3 segundos antes de solicitar otra
    !work_cycle.

+!work_cycle : not state(idle) <-
    .wait(2000);
    !work_cycle.

/* ============================================================================
 * MANEJO DE TAREAS ASIGNADAS
 * ============================================================================ */

// Recibir tarea del scheduler
+task(CId, ShelfId) : state(idle) <-
    .print("[LIGHT] Tarea asignada: Transportar ", CId, " a ", ShelfId);
    -+state(working);
    -+carrying(CId);
    !execute_task(CId, ShelfId).

+task(CId, ShelfId) : not state(idle) <-
    .print("[LIGHT] Ocupado, no puedo aceptar tarea: ", CId).

// Ejecutar la tarea completa
+!execute_task(CId, ShelfId) : true <-
    .print("[LIGHT] Iniciando tarea: ", CId);
    
    // Fase 1: Aproximación a la localización del contenedor
    .print("[LIGHT] Fase 1: Localizando contenedor ", CId);
    get_container_location(CId); 
    .wait(container_pos(CId, _, _), 2000); 
    ?container_pos(CId, CX, CY);
    move_to(CX, CY);
    .wait(500);
    -container_pos(CId, CX, CY);
    .wait(500);
    
    // Fase 2: Recoger el contenedor
    .print("[LIGHT] Fase 2: Recogiendo contenedor ", CId);
    -+state(picking);
    pickup(CId);
    .wait(500);
    
    // Fase 3: Navegar hacia la estantería
    .print("[LIGHT] Fase 3: Transportando a estantería ", ShelfId);
    -+state(carrying);
    !navigate_to_shelf(ShelfId);
    
    // Fase 4: Depositar el contenedor
    .print("[LIGHT] Fase 4: Depositando en ", ShelfId);
    -+state(dropping);
    drop_at(ShelfId);
    .send(supervisor,tell,stored(CId,ShelfId));
    .wait(500);
    
    // Fase 5: Completar y volver a idle
    .print("[LIGHT] Tarea completada: ", CId);
    -+carrying(none);
    -task(CId, ShelfId);

    // Fase 6: Volver al origen
    .print("[LIGHT] Volviendo al origen...");
    move_to(1,3);
    .send(scheduler,tell,ready);
    -+state(idle).

+!navigate_to_shelf(ShelfId) : true <-
    .print("Buscando coordenadas de ", ShelfId);
    get_shelf_info(ShelfId); 
    .wait(100); 
    ?shelf_pos(ShelfId, X, Y); 
    .print("Coordenadas obtenidas: ", X, ",", Y);
    move_to(X, Y);
    .wait(1000);
    -shelf_pos(ShelfId, X, Y).

/* ============================================================================
 * MANEJO DE ERRORES
 * ============================================================================ */

// Error al recoger contenedor (muy pesado o grande)
+error(container_too_heavy, Data) : carrying(CId) <-
    .print("[LIGHT] ERROR: Contenedor muy pesado - ", Data);
    -+state(idle);
    -+carrying(none);
    -task(CId, _).

+error(container_too_big, Data) : carrying(CId) <-
    .print("[LIGHT] ERROR: Contenedor muy grande - ", Data);
    -+state(idle);
    -+carrying(none);
    -task(CId, _).

// Error general
+error(ErrorType, Data) : true <-
    .print("[LIGHT] Error detectado: ", ErrorType, " - ", Data);
    -+state(idle);
    -+carrying(none).

// Confirmación de recogida exitosa
+picked(CId) : true <-
    .print("[LIGHT] Contenedor ", CId, " recogido correctamente").

// Confirmación de almacenamiento exitoso
+stored(CId, ShelfId) : true <-
    .print("[LIGHT] Contenedor ", CId, " almacenado en ", ShelfId).
