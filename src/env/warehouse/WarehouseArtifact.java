package warehouse;

import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

import jason.asSyntax.Literal;
import jason.asSyntax.NumberTerm;
import jason.asSyntax.Structure;
import jason.environment.Environment;

/**
 * Artefacto del almacén automatizado Proporciona la API para que los agentes
 * interactúen con el entorno
 */
public class WarehouseArtifact extends Environment {

    // Dimensiones del almacén
    private static final int GRID_WIDTH = 20;
    private static final int GRID_HEIGHT = 15;

    // Estructuras de datos del almacén
    private CellType[][] grid;
    private Map<String, Robot> robots;
    private Map<String, Container> containers;
    private Map<String, Shelf> shelves;
    private ConcurrentLinkedQueue<Container> pendingContainers;
    private Map<String, String> taskAssignments; // containerId -> robotId

    // GUI visual
    private WarehouseView view;

    // Contadores para generar IDs
    private int containerCounter = 0;

    // Métricas
    private int totalContainersProcessed = 0;
    private int totalErrors = 0;
    private long startTime;

    // Gestión del thread generador de contenedores
    private ExecutorService containerGeneratorExecutor;
    private volatile boolean running = true;

    @Override
    public void init(String[] args) {
        super.init(args);

        // Inicializar estructuras
        grid = new CellType[GRID_WIDTH][GRID_HEIGHT];
        robots = new ConcurrentHashMap<>();
        containers = new ConcurrentHashMap<>();
        shelves = new ConcurrentHashMap<>();
        pendingContainers = new ConcurrentLinkedQueue<>();
        taskAssignments = new ConcurrentHashMap<>();

        // Inicializar grid
        initializeGrid();

        // Crear robots
        initializeRobots();

        // Crear estanterías
        initializeShelves();

        // Crear GUI
        view = new WarehouseView(this, GRID_WIDTH, GRID_HEIGHT);
        view.setVisible(true);

        // Mensaje de bienvenida en la consola
        view.logMessage("✨ ========================================");
        view.logMessage("🏢 Warehouse Management System Initialized");
        view.logMessage("   Grid: " + GRID_WIDTH + "x" + GRID_HEIGHT);
        view.logMessage("   Robots: " + robots.size());
        view.logMessage("   Shelves: " + shelves.size());
        view.logMessage("✨ ========================================");
        view.logMessage("");

        // Enviar percepción inicial de la posición de los robots
        for (Robot r : robots.values()) {
            addPercept(r.getId(), Literal.parseLiteral("robot_at(" + r.getX() + "," + r.getY() + ")"));
        }

        // Iniciar generador de contenedores
        startContainerGenerator();

        // Agregar shutdown hook para limpieza apropiada
        Runtime.getRuntime().addShutdownHook(new Thread(this::stop));

        startTime = System.currentTimeMillis();

        System.out.println("Warehouse environment initialized");
        System.out.println("Grid size: " + GRID_WIDTH + "x" + GRID_HEIGHT);
        System.out.println("Robots: " + robots.size());
        System.out.println("Shelves: " + shelves.size());
    }

    /**
     * Inicializa el grid con zonas
     */
    private void initializeGrid() {
        // Inicializar todos como vacíos
        for (int x = 0; x < GRID_WIDTH; x++) {
            for (int y = 0; y < GRID_HEIGHT; y++) {
                grid[x][y] = CellType.EMPTY;
            }
        }

        // Zona de entrada (arriba izquierda) - 3 filas para admitir contenedores 2x3
        for (int x = 0; x < 3; x++) {
            for (int y = 0; y < 3; y++) {
                grid[x][y] = CellType.ENTRANCE;
            }
        }

        // Zona de clasificación
        for (int x = 3; x < 7; x++) {
            for (int y = 0; y < 2; y++) {
                grid[x][y] = CellType.CLASSIFICATION;
            }
        }
    }

    /**
     * Crea los robots iniciales
     */
    private void initializeRobots() {
        Robot light = new Robot("robot_light", "light", 10, 1, 1, 3);
        light.setPosition(1, 3);
        robots.put("robot_light", light);

        Robot medium = new Robot("robot_medium", "medium", 30, 1, 2, 2);
        medium.setPosition(2, 3);
        robots.put("robot_medium", medium);

        Robot heavy = new Robot("robot_heavy", "heavy", 100, 2, 3, 1);
        heavy.setPosition(3, 3);
        robots.put("robot_heavy", heavy);
    }

    /**
     * Crea las estanterías del almacén
     */
    private void initializeShelves() {
        // Crear estanterías en el área de almacenamiento
        int shelfId = 1;

        // Fila de estanterías pequeñas
        for (int x = 10; x < 18; x += 2) {
            Shelf shelf = new Shelf("shelf_" + shelfId++, x, 2, 2, 2, 50, 8);
            shelves.put(shelf.getId(), shelf);
            grid[x][2] = CellType.SHELF;
            grid[x + 1][2] = CellType.SHELF;
            grid[x][3] = CellType.SHELF;
            grid[x + 1][3] = CellType.SHELF;
        }

        // Fila de estanterías medianas
        for (int x = 10; x < 18; x += 3) {
            Shelf shelf = new Shelf("shelf_" + shelfId++, x, 6, 3, 2, 100, 12);
            shelves.put(shelf.getId(), shelf);
            for (int dx = 0; dx < 3; dx++) {
                grid[x + dx][6] = CellType.SHELF;
                grid[x + dx][7] = CellType.SHELF;
            }
        }

        // Fila de estanterías grandes
        for (int x = 10; x < 16; x += 4) {
            Shelf shelf = new Shelf("shelf_" + shelfId++, x, 10, 4, 3, 200, 20);
            shelves.put(shelf.getId(), shelf);
            for (int dx = 0; dx < 4; dx++) {
                for (int dy = 0; dy < 3; dy++) {
                    grid[x + dx][10 + dy] = CellType.SHELF;
                }
            }
        }
    }

    /**
     * Inicia el generador automático de contenedores
     */
    private void startContainerGenerator() {
        containerGeneratorExecutor = Executors.newSingleThreadExecutor(r -> {
            Thread t = new Thread(r, "ContainerGenerator");
            t.setDaemon(true);
            return t;
        });

        containerGeneratorExecutor.submit(() -> {
            Random rand = new Random();
            while (running) {
                try {
                    Thread.sleep(5000 + rand.nextInt(5000)); // Entre 5 y 10 segundos

                    if (!running) {
                        break;
                    }

                    // Generar contenedor aleatorio
                    Container container = generateRandomContainer();
                    containers.put(container.getId(), container);
                    pendingContainers.offer(container);

                    System.out.println("New container generated: " + container);

                    // Log a la consola de la GUI
                    if (view != null) {
                        view.logMessage(String.format("🆕 New container: %s (%.1fkg, %s)",
                                container.getId(), container.getWeight(), container.getType()));
                    }

                    // Notificar a los agentes
                    addPercept(Literal.parseLiteral("new_container(\"" + container.getId() + "\")"));

                    if (view != null) {
                        view.update();
                    }

                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
            System.out.println("Container generator stopped");
        });
    }

    /**
     * Detiene el entorno de forma limpia
     */
    public void stop() {
        System.out.println("Stopping warehouse environment...");
        running = false;

        if (containerGeneratorExecutor != null) {
            containerGeneratorExecutor.shutdown();
            try {
                if (!containerGeneratorExecutor.awaitTermination(5, TimeUnit.SECONDS)) {
                    containerGeneratorExecutor.shutdownNow();
                }
            } catch (InterruptedException e) {
                containerGeneratorExecutor.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }

        System.out.println("Warehouse environment stopped");
    }

    /**
     * Genera un contenedor aleatorio
     */
    private Container generateRandomContainer() {
        Random rand = new Random();
        String id = "container_" + (++containerCounter);

        // Tamaños posibles: 1x1, 1x2, 2x2, 2x3
        int[][] sizes = {{1, 1}, {1, 2}, {2, 2}, {2, 3}};
        int[] size = sizes[rand.nextInt(sizes.length)];

        // Peso aleatorio
        double weight = 5 + rand.nextDouble() * 95; // 5 a 100 kg

        // Tipo: standard (70%), fragile (15%), urgent (15%)
        String type;
        double r = rand.nextDouble();
        if (r < 0.70) {
            type = "standard";
        } else if (r < 0.85) {
            type = "fragile";
        } else {
            type = "urgent";
        }

        Container container = new Container(id, size[0], size[1], weight, type);
        container.setPosition(1, 0); // Posición inicial en zona de entrada (permite 2x3 sin desbordar)

        return container;
    }

    //Aquí defines que hace al encontrar x nombres
    //Aquí defines que hace al encontrar x nombres
    @Override
    public boolean executeAction(String agName, Structure action) {
        try {
            String actionName = action.getFunctor();

            switch (actionName) {
                case "get_shelf_info": // nos genera una creencia con la localización de la estantería deseada
                    return executeGetShelfInfo(agName, action);
                case "get_container_location": // nos genera una creencia con la localización del contenedor deseado
                    return executeGetContainerLocation(agName, action);
                case "move_to":
                    return executeMoveTo(agName, action);
                case "pickup":
                    return executePickup(agName, action);
                case "drop_at":
                    return executeDropAt(agName, action);
                case "request_task":
                    return executeRequestTask(agName, action);
                case "get_container_info":
                    return executeGetContainerInfo(agName, action);
                case "get_free_shelf":
                    return executeGetFreeShelf(agName, action);
                case "scan_surroundings":
                    return executeScanSurroundings(agName, action);
                default:
                    System.err.println("Unknown action: " + actionName);
                    return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    
    /**
     * Acción: get_shelf_info("shelf_X")
     * Obtiene la posición de la estantería indicada y crea una percepción en el agente.
     * Si la estantería no existe, genera un error para el agente.
     */
    private boolean executeGetShelfInfo(String agName, Structure action) {
        // Extraemos el ID de la estantería de la acción y eliminamos comillas
        String shelfId = action.getTerm(0).toString().replace("\"", "");
        
        // Buscamos la estantería en el mapa de estanterías
        Shelf s = shelves.get(shelfId);
        
        if (s != null) {
            // Si se encuentra, creamos una percepción en el agente con la posición
            // shelf_pos("shelf_X", X, Y)
            addPercept(agName, Literal.parseLiteral(
                "shelf_pos(\"" + shelfId + "\"," + s.getX() + "," + s.getY() + ")"
            ));
            // Acción ejecutada correctamente
            return true;
        } else {
            // Si no se encuentra, registramos un error para el agente
            addError(agName, "shelf_not_found", shelfId);
            // Indicamos que la acción falló
            return false;
        }
    }

    /**
    * Acción: move_to(X, Y)
    * Mueve al robot paso a paso hacia la posición indicada, evitando obstáculos y otros robots.
    * Actualiza la percepción del robot con su nueva posición y simula su velocidad según el tipo de robot.
    */
    private boolean executeMoveTo(String agName, Structure action) {
        try {
            // ubica a donde queremos mover al robot
            int targetX = (int) ((NumberTerm) action.getTerm(0)).solve();
            int targetY = (int) ((NumberTerm) action.getTerm(1)).solve();

            // busca que el robot exista
            Robot robot = robots.get(agName);
            if (robot == null) {
                addError(agName, "robot_not_found", "Robot " + agName + " not found");
                return false;
            }

            int currentX = robot.getX();
            int currentY = robot.getY();

            // Verificar límites del escenario
            if (targetX < 0 || targetX >= GRID_WIDTH || targetY < 0 || targetY >= GRID_HEIGHT) {
                addError(agName, "illegal_move", "Position out of bounds: (" + targetX + "," + targetY + ")");
                return false;
            }

            // Verificar si hay obstáculos (excepto estanterías que son destinos válidos)
            if (grid[targetX][targetY] == CellType.BLOCKED) {
                addError(agName, "route_blocked", "Position blocked: (" + targetX + "," + targetY + ")");
                return false;
            }

            while (currentX != targetX || currentY != targetY) {

                // Calcular el siguiente paso en X
                int stepX = Integer.compare(targetX, currentX); // -1, 0 o 1
                // Calcular el siguiente paso en Y
                int stepY = Integer.compare(targetY, currentY); // -1, 0 o 1

                int nextX = currentX + stepX;
                int nextY = currentY + stepY;

                // Verificar si hay otro robot en la posición de destino
                boolean occupied = false;
                for (Robot other : robots.values()) {
                    if (!other.getId().equals(agName) && other.getX() == nextX && other.getY() == nextY) {
                        occupied = true;
                        break;
                    }
                }

                // Si la celda siguiente está ocupada o bloqueada, buscar alternativas
                if (occupied || grid[nextX][nextY] == CellType.BLOCKED) {

                    boolean moved = false;

                    // Lista de todas las celdas adyacentes posibles (incluyendo diagonales)
                    int[][] directions = {
                        {1, 0}, {-1, 0}, {0, 1}, {0, -1}, // ortogonales
                        {1, 1}, {1, -1}, {-1, 1}, {-1, -1} // diagonales
                    };

                    double minDistance = Double.MAX_VALUE;
                    int bestX = currentX;
                    int bestY = currentY;

                    for (int[] d : directions) {
                        int altX = currentX + d[0];
                        int altY = currentY + d[1];

                        // Verificar límites y que no sea bloqueada
                        if (altX >= 0 && altX < GRID_WIDTH
                                && altY >= 0 && altY < GRID_HEIGHT
                                && grid[altX][altY] != CellType.BLOCKED) {

                            // Verificar ocupación
                            boolean altOccupied = false;
                            for (Robot other : robots.values()) {
                                if (!other.getId().equals(agName) && other.getX() == altX && other.getY() == altY) {
                                    altOccupied = true;
                                    break;
                                }
                            }

                            // Busca que dirección es la más optima para llegar al destino, siempre que esta esté disponible
                            if (!altOccupied) {
                                double distance = Math.sqrt(Math.pow(targetX - altX, 2) + Math.pow(targetY - altY, 2));
                                if (distance < minDistance) {
                                    minDistance = distance;
                                    bestX = altX;
                                    bestY = altY;
                                    moved = true;
                                }
                            }
                        }
                    }

                    if (moved) {
                        nextX = bestX;
                        nextY = bestY;
                    } else {
                        // No hay alternativas libres: esperar
                        if (view != null) {
                            view.logMessage("⏳ " + agName + " waiting, no alternative path");
                        }
                        Thread.sleep(200);
                        continue;
                    }
                }

                // Mover al robot
                robot.setPosition(nextX, nextY);

                if (view != null) {
                    view.logMessage(String.format("➡️  %s moved to (%d,%d)", agName, nextX, nextY));
                }

                // Actualizar percepción
                removePerceptsByUnif(agName, Literal.parseLiteral("robot_at(_,_)"));
                addPercept(agName, Literal.parseLiteral("robot_at(" + nextX + "," + nextY + ")"));

                // Log a la consola de la GUI
                if (view != null) {
                    view.logMessage(String.format("➡️  %s moved to (%d,%d)", agName, nextX, nextY));
                }

                // Actualizar percepción
                removePerceptsByUnif(agName, Literal.parseLiteral("robot_at(_,_)"));
                addPercept(agName, Literal.parseLiteral("robot_at(" + nextX + "," + nextY + ")"));

                if (view != null) {
                    view.update();
                }

                currentX = nextX;
                currentY = nextY;

                //Segun el tipo de robot que varíe la velocidad
                if (robot.getSpeed() == 3) {
                    Thread.sleep(200);
                }
                if (robot.getSpeed() == 2) {
                    Thread.sleep(400);
                }
                if (robot.getSpeed() == 1) {
                    Thread.sleep(600);
                }
            }

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: pickup(ContainerId) Recoge un contenedor
     */
    private boolean executePickup(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");

            Robot robot = robots.get(agName);
            Container container = containers.get(containerId);

            if (robot == null || container == null) {
                addError(agName, "invalid_pickup", "Robot or container not found");
                return false;
            }

            // Verificar distancia
            if (robot.distanceTo(container.getX(), container.getY()) > 1) {
                addError(agName, "too_far", "Container too far away");
                return false;
            }

            // Verificar capacidad
            if (!robot.canCarry(container)) {
                if (container.getWeight() > robot.getMaxWeight()) {
                    addError(agName, "container_too_heavy",
                            "Container " + containerId + " is too heavy for " + agName);
                } else {
                    addError(agName, "container_too_big",
                            "Container " + containerId + " is too big for " + agName);
                }
                return false;
            }

            // Recoger contenedor
            if (robot.pickup(container)) {
                container.setPicked(true);
                addPercept(agName, Literal.parseLiteral("picked(\"" + containerId + "\")"));

                if (view != null) {
                    view.logMessage(
                            String.format("📦 %s picked up %s (%.1fkg)", agName, containerId, container.getWeight()));
                    view.update();
                }

                return true;
            }

            return false;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: drop_at(ShelfId) Deposita el contenedor en una estantería
     */
    private boolean executeDropAt(String agName, Structure action) {
        try {
            String shelfId = action.getTerm(0).toString().replace("\"", "");

            Robot robot = robots.get(agName);
            Shelf shelf = shelves.get(shelfId);

            if (robot == null || shelf == null) {
                addError(agName, "invalid_drop", "Robot or shelf not found");
                return false;
            }

            if (!robot.isCarrying()) {
                addError(agName, "not_carrying", "Robot is not carrying anything");
                return false;
            }

            // Verificar distancia a la estantería
            if (robot.distanceTo(shelf.getX(), shelf.getY()) > 2) {
                addError(agName, "too_far", "Shelf too far away");
                return false;
            }

            Container container = robot.getCarriedContainer();

            // Verificar si cabe en la estantería
            if (!shelf.canStore(container)) {
                addError(agName, "shelf_full", "Shelf " + shelfId + " cannot store container");
                return false;
            }

            // Depositar
            shelf.store(container);
            robot.drop();
            container.setAssignedShelf(shelfId);

            //para que el robot deje de estar ocupado
            robot.setBusy(false);
            robot.setCurrentTask(null);
            taskAssignments.remove(container.getId());

            totalContainersProcessed++;

            // Actualizar percepciones
            removePerceptsByUnif(agName, Literal.parseLiteral("picked(_)"));
            addPercept(agName, Literal.parseLiteral("stored(\"" + container.getId() + "\",\"" + shelfId + "\")"));

            if (view != null) {
                view.logMessage(String.format("✅ %s stored %s at %s", agName, container.getId(), shelfId));
                view.update();
            }

            System.out.println(agName + " stored " + container.getId() + " at " + shelfId);

            if (view != null) {
                view.update();
            }

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: request_task() Solicita una nueva tarea del scheduler
     */
    private boolean executeRequestTask(String agName, Structure action) {
        try {
            Robot robot = robots.get(agName);
            if (robot == null) {
                return false;
            }

            // Si ya está ocupado, no asignar nueva tarea
            if (robot.isBusy() || robot.isCarrying()) {
                return true;
            }

            // Buscar contenedor pendiente
            Container container = pendingContainers.poll();
            if (container == null) {
                return true; // No hay tareas pendientes
            }

            // Verificar si el robot puede manejar el contenedor
            if (!robot.canCarry(container)) {
                // Devolver a la cola
                pendingContainers.offer(container);
                return true;
            }

            // Buscar estantería apropiada
            Shelf bestShelf = findBestShelfForRobot(container, agName);
            //Shelf bestShelf = findBestShelf(container);
            if (bestShelf == null) {
                // No hay estanterías disponibles, devolver a la cola
                pendingContainers.offer(container);
                addError(agName, "no_shelf_available", "No shelf available for container");
                return true;
            }

            // Asignar tarea
            taskAssignments.put(container.getId(), agName);
            robot.setBusy(true);
            robot.setCurrentTask(container.getId());

            // Notificar al agente
            addPercept(agName, Literal.parseLiteral(
                    "task(\"" + container.getId() + "\",\"" + bestShelf.getId() + "\")"));

            System.out.println("Task assigned to " + agName + ": " + container.getId() + " -> " + bestShelf.getId());

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Encuentra la mejor estantería para un contenedor
     */
    private Shelf findBestShelf(Container container) {
        List<Shelf> availableShelves = shelves.values().stream()
                .filter(s -> s.canStore(container))
                .sorted(Comparator.comparingDouble(Shelf::getOccupancyPercentage))
                .collect(Collectors.toList());

        return availableShelves.isEmpty() ? null : availableShelves.get(0);
    }

    private Shelf findBestShelfForRobot(Container container, String robotId) {
        return shelves.values().stream()
                .filter(shelf -> shelf.canStore(container))
                .filter(shelf -> {
                    String id = shelf.getId();

                    if (robotId.equalsIgnoreCase("robot_light")) {
                        return id.equals("shelf_1") || id.equals("shelf_2")
                                || id.equals("shelf_3") || id.equals("shelf_4");
                    }

                    if (robotId.equalsIgnoreCase("robot_medium")) {
                        return id.equals("shelf_5") || id.equals("shelf_6")
                                || id.equals("shelf_7");
                    }

                    if (robotId.equalsIgnoreCase("robot_heavy")) {
                        return id.equals("shelf_8") || id.equals("shelf_9");
                    }

                    return false;
                })
                .sorted(Comparator.comparingDouble(Shelf::getOccupancyPercentage))
                .findFirst()
                .orElse(null);
    }

    /**
     * Acción: get_container_info(ContainerId) Obtiene información sobre un
     * contenedor
     */
    private boolean executeGetContainerInfo(String agName, Structure action) {
        try {
            String containerId = action.getTerm(0).toString().replace("\"", "");
            Container container = containers.get(containerId);

            if (container == null) {
                return false;
            }

            // Agregar percepción con información del contenedor
            addPercept(agName, Literal.parseLiteral(
                    "container_info(\"" + containerId + "\","
                    + container.getWidth() + ","
                    + container.getHeight() + ","
                    + container.getWeight() + ",\""
                    + container.getType() + "\")"));

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Acción: get_container_location(ContainerId)
     * Obtiene la posición actual de un contenedor en el almacén y se la proporciona
     * al agente como percepción, generando la creencia container_pos(ContainerId, X, Y).
     * Si el contenedor no existe, se registra un error.
     */
    private boolean executeGetContainerLocation(String agName, Structure action) {
        try {
            // Extraer y limpiar el ID del contenedor del primer término de la acción
            String containerId = action.getTerm(0).toString().replace("\"", "");
    
            // Buscar el contenedor en el mapa de contenedores del almacén
            Container container = containers.get(containerId);
    
            if (container != null) {
                // Eliminar percepciones anteriores de este contenedor si existen
                removePerceptsByUnif(agName, Literal.parseLiteral("container_pos(\"" + containerId + "\", _, _)"));
    
                // Añadir nueva percepción con la ubicación actual del contenedor
                // Esto crea una creencia en el agente: container_pos("container_X", X, Y)
                addPercept(agName, Literal.parseLiteral(
                        "container_pos(\"" + containerId + "\"," + container.getX() + "," + container.getY() + ")"
                ));
    
                return true;
            } else {
                // Contenedor no encontrado: registrar error para el agente
                addError(agName, "container_not_found", containerId);
                return false;
            }
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

   /**
     * Acción: get_free_shelf(ContainerId, RobotName)
     * Obtiene una estantería libre adecuada para un contenedor según la zona asignada
     * al robot (light, medium, heavy) y la capacidad disponible.
     * Genera la percepción free_shelf(ContainerId, ShelfId) para el agente scheduler.
     * Si no se encuentra ninguna estantería válida, devuelve un error implícito.
     */
    private boolean executeGetFreeShelf(String agName, Structure action) {
        try {
            // Obtener y limpiar los parámetros de entrada
            String containerId = action.getTerm(0).toString().replace("\"", "");
            String targetRobot = action.getTerm(1).toString().toLowerCase();
    
            // Recuperar el contenedor del almacén
            Container container = containers.get(containerId);
            if (container == null) {
                view.logMessage("Error: contenedor " + containerId + " no encontrado.");
                return false;
            }
    
            // Filtrar estanterías que pueden almacenar el contenedor y que no estén llenas
            List<Shelf> capableShelves = shelves.values().stream()
                    .filter(s -> s.canStore(container) && !s.isFull())
                    .collect(Collectors.toList());
    
            // Selección de la estantería según la zona correspondiente al tipo de robot
            Shelf selectedShelf = null;
    
            if (targetRobot.contains("light")) {
                // Robots light: buscar estanterías 1 a 4
                selectedShelf = capableShelves.stream()
                        .filter(s -> s.getId().matches("shelf_[1-4]"))
                        .findFirst().orElse(null);
            } else if (targetRobot.contains("medium")) {
                // Robots medium: buscar estanterías 5 a 7
                selectedShelf = capableShelves.stream()
                        .filter(s -> s.getId().matches("shelf_[5-7]"))
                        .findFirst().orElse(null);
            } else if (targetRobot.contains("heavy")) {
                // Robots heavy: buscar estanterías 8 y 9
                selectedShelf = capableShelves.stream()
                        .filter(s -> s.getId().matches("shelf_[8-9]"))
                        .findFirst().orElse(null);
            }
    
            // Si se encuentra una estantería válida, enviar percepción al Scheduler
            if (selectedShelf != null) {
                // Eliminar percepciones antiguas del contenedor para evitar duplicados
                removePercept(agName, Literal.parseLiteral("free_shelf(\"" + containerId + "\", _)"));
    
                // Añadir percepción con la estantería seleccionada
                addPercept(agName, Literal.parseLiteral(
                        "free_shelf(\"" + containerId + "\",\"" + selectedShelf.getId() + "\")"
                ));
    
                return true;
            }
    
            // No se encontró estantería adecuada
            return false;
    
        } catch (Exception e) {
            // En caso de cualquier excepción, devolver false
            return false;
        }
    }

    /**
     * Acción: scan_surroundings() Escanea las celdas alrededor del robot
     */
    private boolean executeScanSurroundings(String agName, Structure action) {
        try {
            Robot robot = robots.get(agName);
            if (robot == null) {
                return false;
            }

            int x = robot.getX();
            int y = robot.getY();

            // Escanear celdas adyacentes
            for (int dx = -2; dx <= 2; dx++) {
                for (int dy = -2; dy <= 2; dy++) {
                    int nx = x + dx;
                    int ny = y + dy;

                    if (nx >= 0 && nx < GRID_WIDTH && ny >= 0 && ny < GRID_HEIGHT) {
                        CellType type = grid[nx][ny];
                        addPercept(agName, Literal.parseLiteral(
                                "cell(" + nx + "," + ny + "," + type.name().toLowerCase() + ")"));

                        if (type == CellType.BLOCKED) {
                            addPercept(agName, Literal.parseLiteral("blocked(" + nx + "," + ny + ")"));
                        }
                    }
                }
            }

            return true;

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    /**
     * Agrega un error a las percepciones
     */
    private void addError(String agName, String errorType, String data) {
        totalErrors++;
        addPercept(agName, Literal.parseLiteral(
                "error(" + errorType + ",\"" + data + "\")"));
        System.err.println("ERROR [" + agName + "]: " + errorType + " - " + data);
    }

    // Getters para la vista
    public CellType[][] getGrid() {
        return grid;
    }

    public Map<String, Robot> getRobots() {
        return robots;
    }

    public Map<String, Container> getContainers() {
        return containers;
    }

    public Map<String, Shelf> getShelves() {
        return shelves;
    }

    public int getPendingContainersCount() {
        return pendingContainers.size();
    }

    public int getTotalContainersProcessed() {
        return totalContainersProcessed;
    }

    public int getTotalErrors() {
        return totalErrors;
    }

    public String getStatistics() {
        long elapsedTime = (System.currentTimeMillis() - startTime) / 1000;
        return String.format(
                "Time: %ds | Processed: %d | Pending: %d | Errors: %d",
                elapsedTime, totalContainersProcessed, pendingContainers.size(), totalErrors);
    }
}
