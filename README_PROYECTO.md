#11-03-2026 [Alexis]
La última modificación que hice fue la función executeMoveTo en WarehouseArtifacts. Con esta cambié la función move_to para que los robots se muevan paso a paso a sus posiciones adyacentes yendo a la posición que se les indica. También está implementado que, en caso de que se encuentre un obstáculo, analice qué posición le conviene más llegar a su destino.
No sé si se necesitaría algo más para completar la entrega de esta semana. Cualquier cosa comentadme.

#16-03-2026 [copilot]
Correcciones de bugs críticos que impedían el funcionamiento correcto del sistema:

1. **robot.setBusy nunca se reseteaba** (WarehouseArtifact.java): Tras completar un drop_at con éxito, el robot quedaba marcado como ocupado para siempre y nunca recibía nuevas tareas. Añadido robot.setBusy(false) y robot.setCurrentTask(null) en executeDropAt.

2. **Pickup fallido dejaba al robot bloqueado** (WarehouseArtifact.java): Si un contenedor era demasiado pesado/grande para un robot, este quedaba marcado como busy sin poder recibir nuevas tareas. Ahora se resetea el estado y el contenedor vuelve a la cola de pendientes.

3. **robot_medium.asl duplicado** : El fichero contenía el código íntegro dos veces, y la segunda copia usaba move_to_safe (acción inexistente en el artefacto Java). Eliminado el duplicado.

4. **robot_light.asl con planes en conflicto**: Había dos planes +task(CId,ShelfId):true antes de los planes correctos, lo que hacía que la ejecución real de tareas nunca se alcanzara. Eliminados los planes duplicados/incompletos.

5. **navigate_to_shelf con posiciones hardcodeadas**: Los tres robots navegaban a coordenadas fijas ignorando la estantería asignada, haciendo que drop_at fallara por distancia. Añadidas creencias shelf_pos/3 con las posiciones reales de cada estantería y adaptados los planes navigate_to_shelf de los tres robots.

6. **scheduler.asl con plan container_info duplicado**: Había dos planes +container_info con contexto true, por lo que el segundo nunca se ejecutaba. Fusionados en uno solo.

7. **supervisor.asl sin planes**: El agente supervisor tenía solo creencias pero ningún plan. Añadidos planes básicos de monitorización (!start, !monitor_loop, +new_container, +error).
