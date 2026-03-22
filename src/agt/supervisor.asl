/*******************************************************************************

 * SUPERVISOR - Gestión de Almacén (Fase 1)

 ******************************************************************************/



/* --- CREENCIAS --- */

total_received(0).

total_stored(0).

total_errors(0).

// Inicialización de tipos de error  

errors_by_type(container_too_heavy, 0).

errors_by_type(container_too_big, 0).

errors_by_type(shelf_full, 0).

errors_by_type(illegal_move, 0).

errors_by_type(conflict, 0).

errors_by_type(route_blocked, 0).



/* --- INICIO --- */

!start.

+!start : true <-

    .print("Supervisor activo: Monitorizando flujo y errores");

    !periodic_stats.



/* --- MONITORIZACIÓN --- */

// Registro de entradas

+new_container(CId) : true <-

    ?total_received(N); -+total_received(N+1).



// Registro de éxitos

+stored(CId, ShelfId) : true <-

    ?total_stored(S); -+total_stored(S+1);

    .print("Contenedor ", CId, " en estantería ", ShelfId).



// Gestión de errores detectados

+error(Type, Data) : true <-

    ?total_errors(E); -+total_errors(E+1);

    ?errors_by_type(Type, C); -+errors_by_type(Type, C+1);

    .print("Error tipo: ", Type, " | Datos: ", Data).



/* --- ESTADÍSTICAS --- */

+!periodic_stats : true <-

    ?total_received(R); ?total_stored(S); ?total_errors(E);

    .print("--- ESTADO ACTUAL ---");

    .print("Recibidos: ", R, " | Almacenados: ", S, " | Errores: ", E);

    if (R > 0) { .print("Eficiencia: ", (S/R)*100, "%") };

    .wait(20000);

    !periodic_stats. //explica cada llinea de este codigo
