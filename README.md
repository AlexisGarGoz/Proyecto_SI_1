README

Sistema inteligente de gestión logística de almacén con robots autónomos, un scheduler y un supervisor para controlar tareas, errores y estadísticas.

1️. Descripción General

El sistema simula un almacén automatizado donde:

Los contenedores llegan a la zona de entrada.
Se asignan a robots según tamaño, peso y disponibilidad.
Los robots transportan los contenedores hasta la estantería correspondiente.
Un scheduler coordina tareas y optimiza la asignación.
Un supervisor monitorea entradas, almacenamientos, errores y eficiencia.

El entorno es controlado por un artefacto Java (WarehouseArtifact) que gestiona la simulación y comunica percepciones a los agentes Jason.

2️. Componentes Principales
2.1 Robots

Se definen tres tipos de robots:

Robot	        Peso Máx	Tamaño Máx	Velocidad	Capacidad	Estado Inicial
robot_light	  10 kg	    1x1	        3	         Ligero	  idle
robot_medium	30 kg	    1x2	        2	         Medio	  idle
robot_heavy	  100 kg	  2x3	        1	         Pesado	  idle

Estados posibles:

idle → disponible
moving → en tránsito
picking → recogiendo contenedor
carrying → transportando contenedor
dropping → depositando contenedor

Acciones soportadas:

move_to(X,Y) → movimiento paso a paso con detección de obstáculos y colisiones.
pickup(ContainerId) → recoger contenedor.
drop_at(ShelfId) → depositar contenedor.
request_task() → solicitar tarea al scheduler.
scan_surroundings() → percepción de celdas cercanas.
2.2 Scheduler (Jason Agent)

Responsable de:

Recibir nuevos contenedores.
Clasificar contenedores según peso, tamaño y tipo.
Asignar tareas a robots disponibles según sus capacidades.
Optimizar la distribución para maximizar eficiencia.
Gestionar cola de contenedores pendientes.
Notificar errores al supervisor.

Flujo principal:

+new_container(CId) → obtiene info (get_container_info) y decide qué robot puede manejarlo.
+container_info(CId, ...) → asigna robot o añade a cola si no hay disponible.
+free_shelf(CId, ShelfId) → envía tarea al robot asignado.
+ready[source(Robot)] → robot vuelve a disponible y revisa cola.
Manejo de errores: container_too_heavy, container_too_big, shelf_full, route_blocked, conflict, illegal_move.

3️. Supervisor

El supervisor se encarga de la monitorización general del almacén:

Registra contenedores recibidos y almacenados.
Controla errores y mantiene estadísticas por tipo de error.
Calcula la eficiencia del almacén en tiempo real.

Creencias iniciales:

total_received(0).
total_stored(0).
total_errors(0).

errors_by_type(container_too_heavy, 0).
errors_by_type(container_too_big, 0).
errors_by_type(shelf_full, 0).
errors_by_type(illegal_move, 0).
errors_by_type(conflict, 0).
errors_by_type(route_blocked, 0).

Acciones principales:

+new_container(CId) → incrementa total recibido.
+stored(CId, ShelfId) → incrementa total almacenado y loggea la acción.
+error(Type, Data) → incrementa contador de errores y reporta el tipo.
+!periodic_stats → imprime estadísticas periódicas de eficiencia.

4️. WarehouseArtifact

El artefacto Java proporciona la simulación física del almacén y la API de interacción para los agentes Jason.

4.1 Funcionalidades
Mantiene un grid de 20x15 representando el almacén.
Gestiona robots, contenedores y estanterías.
Simula movimiento paso a paso de robots con detección de obstáculos y colisiones.
Genera contenedores aleatorios con distintos tamaños, pesos y tipos.
Asigna tareas según capacidad de robot y disponibilidad de estanterías.
Reporta percepciones a los agentes Jason.
Mantiene métricas como total containers processed, pending containers, total errors.
4.2 Acciones implementadas
Acción Jason	Descripción
get_shelf_info(ShelfId)	Retorna la posición de la estantería para el agente.
get_container_location(ContainerId)	Retorna la posición actual del contenedor.
move_to(X,Y)	Mueve el robot paso a paso hacia la posición indicada.
pickup(ContainerId)	Recoge un contenedor si está dentro de rango y el robot tiene capacidad.
drop_at(ShelfId)	Deposita el contenedor en la estantería, actualiza percepciones y libera el robot.
request_task()	Solicita un contenedor pendiente y asigna la estantería adecuada.
get_container_info(ContainerId)	Obtiene información del contenedor (peso, tamaño, tipo).
get_free_shelf(ContainerId, RobotName)	Devuelve la estantería libre más adecuada según tipo de robot.
scan_surroundings()	Escanea celdas alrededor del robot y actualiza percepciones sobre obstáculos.

5️. Flujo de Ejecución
El entorno WarehouseArtifact inicializa:
Grid, robots, estanterías y GUI.
Generador de contenedores aleatorios.
Se inicia el Supervisor con estadísticas y monitorización.
El Scheduler recibe la percepción new_container:
Clasifica el contenedor.
Asigna robot disponible según capacidad.
Solicita estantería libre y envía tarea al robot.
El Robot ejecuta la tarea:
move_to → se aproxima al contenedor.
pickup → recoge el contenedor.
navigate_to_shelf → se dirige a la estantería asignada.
drop_at → deposita el contenedor.
Retorna a estado idle y notifica ready al scheduler.
Errores como container_too_heavy, shelf_full o route_blocked son gestionados por Supervisor y Scheduler.
El Supervisor mantiene estadísticas de eficiencia y logs.

6️. Notas de Uso
Cada robot tiene capacidades y zonas específicas de estanterías:
robot_light → shelves 1-4
robot_medium → shelves 5-7
robot_heavy → shelves 8-9
El sistema evita colisiones y movimientos ilegales.
Los contenedores se generan automáticamente cada 5–10 segundos.
El sistema imprime logs y actualiza la GUI en tiempo real.
