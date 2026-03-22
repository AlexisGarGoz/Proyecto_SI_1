/*******************************************************************************
 * SCHEDULER - Agente Planificador y Coordinador de Tareas
 * 
 * Universidad de Vigo - Sistemas Inteligentes
 * Curso 2025-2026
 * 
 * RESPONSABILIDADES:
 *   1. Recibir notificaciones de nuevos contenedores
 *   2. Clasificar contenedores según peso, tamaño, tipo (urgente, frágil)
 *   3. Asignar tareas a robots según sus capacidades
 *   4. Optimizar la asignación para maximizar eficiencia
 *   5. Gestionar colas de contenedores pendientes
 *   6. Coordinar con supervisor para manejo de errores
 * 
 ******************************************************************************/

/* ============================================================================
 * CREENCIAS INICIALES - Base de Conocimiento
 * ============================================================================ */

/* Capacidades de los robots */
robot_capacity(robot_light, 10, 1, 1, 3).    // (Robot, MaxPeso, MaxW, MaxH, Velocidad)
robot_capacity(robot_medium, 30, 1, 2, 2).
robot_capacity(robot_heavy, 100, 2, 3, 1).

/* Estados de los robots */
robot_available(robot_light).
robot_available(robot_medium).
robot_available(robot_heavy).

/* Contadores y estadísticas */
total_containers_received(0).
total_tasks_assigned(0).
pending_containers(0).

// 1. Reaccionar a nuevo contenedor
+new_container(CId) : true <-
    .print("Nuevo contenedor: ", CId);
    get_container_info(CId).



// 2. RECIBIR INFO Y CLASIFICAR

// CASO A: Peso para Robot Ligero y está disponible
+container_info(CId, W, H, Weight, Type) 
    : Weight <= 10 & robot_available(robot_light) 
    <-
    .print("Asignando ", CId, " (", Weight, "kg) a robot_light");
    -robot_available(robot_light);
    +assigning(CId, robot_light);
    get_free_shelf(CId).

// CASO B: Peso para Robot Medio y está disponible
+container_info(CId, W, H, Weight, Type) 
    : Weight <= 30 & robot_available(robot_medium) 
    <-
    .print("Asignando ", CId, " (", Weight, "kg) a robot_medium");
    -robot_available(robot_medium);
    +assigning(CId, robot_medium);
    get_free_shelf(CId).

// CASO C: Peso para Robot Pesado y está disponible
+container_info(CId, W, H, Weight, Type) 
    : Weight <= 100 & robot_available(robot_heavy) 
    <-
    .print("Asignando ", CId, " (", Weight, "kg) a robot_heavy");
    -robot_available(robot_heavy);
    +assigning(CId, robot_heavy);
    get_free_shelf(CId).

// CASO D: Si ningún plan anterior se ejecutó
// (Porque los robots están ocupados o el peso no encaja)
+container_info(CId, W, H, Weight, Type) : true <-
    .print("No hay robots disponibles para ", CId, ". Añadiendo a cola de espera.");
    +pending_container(CId, Weight).



// 3. Cuando Java te contesta con la estantería:
+free_shelf(CId, SId) : assigning(CId, Robot) <- 
    .send(Robot, tell, task(CId, SId)); // <--- AQUÍ MANDAS LA ORDEN REAL
    -assigning(CId, Robot);             // Limpias tu memoria temporal
    .print("Orden enviada a ", Robot, " para llevar ", CId, " a ", SId).


// 4. Cuando un robot manda "ready", lo volvemos a poner en la lista de disponibles
+ready[source(Robot)] : true <-
    .print("El robot ", Robot, " está libre. Revisando cola de espera...");
    +robot_available(Robot); // Recupera la creencia de disponibilidad
    !revisar_cola.           // Crea un objetivo para mirar si hay cajas pendientes  


// Caso A: Hay una caja en la cola que el robot disponible y PUEDE llevar la caja
+!revisar_cola : robot_available(R) & pending_container(CId, Weight) 
                 & robot_capacity(R, MaxW, _, _, _) & Weight <= MaxW <-
    .print("Sacando de la cola: ", CId, " para el robot ", R);
    -pending_container(CId, Weight); // Lo quitamos de la cola
    -robot_available(R);             // Lo volvemos a marcar como ocupado
    +assigning(CId, R);              // Registramos la asignación temporal
    get_free_shelf(CId).             // Pedimos la estantería a Java

// Caso B: No hay nada en la cola o el robot no puede con lo que hay
+!revisar_cola : true <- 
    .print("No hay tareas compatibles en la cola por ahora.").

// ERRORES

+error(container_too_heavy, Data) : assigning(CId, Robot) <-
    .print("Error de peso: ", Robot, " no pudo con ", CId);
    -assigning(CId, Robot);          // Borra la asignación fallida
    +pending_container(CId, 100);    // Lo reencola con un peso alto para que lo coja el Heavy
    .send(supervisor, tell, error_log(container_too_heavy, CId)).

+error(container_too_big, Data) : assigning(CId, Robot) <-
    .print("Error de tamaño: ", CId, " no cabe en ", Robot);
    -assigning(CId, Robot);
    +pending_container(CId, 0); // Lo devuelve a la cola
    .send(supervisor, tell, error_log(container_too_big, CId)).


// Error ESTANTERÍA llena
+error(shelf_full, SId) : task(CId, SId) <-
    .print("Estantería ", SId, " llena. Reasignando destino para ", CId);
    get_free_shelf(CId); // Solicita una nueva estantería al WarehouseArtifact
    .send(supervisor, tell, error_log(shelf_full, SId)).

// Cuando el Java responda con la nueva estantería (SId2)
+free_shelf(CId, SId2) : task(CId, SIdOld) <-
    -task(CId, SIdOld);
    +task(CId, SId2);
    .send(Robot, tell, task(CId, SId2)). // Actualiza la orden al robot


// El Scheduler detecta que un robot está bloqueado
+error(route_blocked, Data) : assigning(CId, Robot) | task(CId, _) <-
    .print("Robot bloqueado en ruta. Cancelando tarea de: ", CId);
    
    // 1. Informar al Supervisor del problema estructural
    .send(supervisor, tell, navigation_error(route_blocked, CId));
    
    // 2. Recuperar el contenedor y ponerlo en la cola de espera
    // (Añadimos el peso 0 de forma temporal o pedimos info de nuevo)
    +pending_container(CId, 0); 
    
    // 3. Limpiar la asignación actual para que el robot pueda reiniciarse
    -assigning(CId, Robot);
    .print("Contenedor ", CId, " devuelto a la cola por bloqueo de ruta.").


// Manejo de colisiones o movimientos fuera de límites
+error(ErrorType, Data) : (ErrorType == conflict | ErrorType == illegal_move) 
                          & assigning(CId, Robot) <-
    .print("ERROR CRÍTICO de navegación (", ErrorType, ") con el contenedor: ", CId);
    
    // Notificar al supervisor para que registre el fallo grave
    .send(supervisor, tell, critical_navigation_error(ErrorType, Robot));
    
    // Devolver el paquete a la cola para que otro robot lo gestione
    +pending_container(CId, 0);
    -assigning(CId, Robot);
    
    // Opcional: Podrías intentar resetear el estado del robot si fuera necesario
    .send(Robot, tell, reset_state).
