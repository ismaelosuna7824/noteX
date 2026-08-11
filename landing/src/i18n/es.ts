import type { Content } from './types';

/*
  Neutral, professional Spanish — no regional voseo. The page is read from
  Mexico, Spain, Argentina and everywhere between, and a regional register
  would quietly exclude most of them.

  Translated as copy, not word by word: the English lines were written to a
  rhythm, and a literal rendering keeps the words while losing the argument.
*/
export const es: Content = {
  htmlLang: 'es',
  hreflang: 'es',
  languageName: 'Español',
  switchLanguageLabel: 'View in English',

  meta: {
    tagline: 'Sumérgete en tus notas',
    description:
      'Una aplicación de notas de escritorio para Windows, macOS y Linux. Edición en Markdown con vista previa en vivo, notas enlazadas, vista de grafo, notas diarias, temporizador de enfoque y sincronización opcional en la nube — con tus notas siempre exportables como Markdown plano.',
    shortDescription:
      'Notas en Markdown que se sienten como un lugar donde da gusto escribir. Gratis y de código abierto.',
  },

  nav: {
    features: 'Funciones',
    graph: 'Grafo',
    tour: 'Recorrido',
    faq: 'Preguntas',
    download: 'Descargar',
    skipToContent: 'Saltar al contenido',
    footerLabel: 'Pie de página',
    sourceCode: 'Código fuente',
    releases: 'Versiones',
    githubLabel: 'GitHub',
  },

  hero: {
    windowLabel: 'NoteX',
    videoLabel:
      'Grabación de pantalla de NoteX: escribiendo una nota, cambiando a vista dividida y navegando el calendario',
    starsSuffix: 'en GitHub',
    starsFallback: 'Código abierto en GitHub',
    licensed: 'Licencia MIT',
    noAccount: 'Sin cuenta',
    headlineLead: 'Escribir debería',
    headlineAccent: 'sentirse así.',
    subheading:
      'Notas en Markdown con vista previa en vivo, enlaces entre tus páginas, una nota para cada día y un temporizador de enfoque — guardadas como archivos planos que puedes llevarte.',
    ctaPrimary: 'Descargar gratis',
    ctaSecondary: 'Verlo en acción',
    platforms: 'Windows · macOS · Linux',
  },

  values: {
    ariaLabel: 'De un vistazo',
    items: [
      { label: 'Vista previa en vivo', detail: 'Mientras escribes' },
      { label: 'Notas enlazadas', detail: 'Escribe @ para conectar' },
      { label: 'Página diaria', detail: 'Lista al abrir' },
      { label: 'Diagramas mermaid', detail: 'Se dibujan al escribir' },
    ],
  },

  features: {
    heading: 'Todo lo que una app de notas debería tener.',
    headingMuted: 'Nada de lo que no.',
    body: 'Hecha para quien escribe todos los días y quiere que sus palabras sigan siendo suyas — Markdown plano en disco, sin ataduras, sin suscripción.',
    items: {
      markdown: {
        title: 'Markdown de principio a fin',
        body: 'El sabor completo de GitHub: tablas, listas de tareas, notas al pie, avisos destacados, código con resaltado de sintaxis y atajos de emoji. Vista previa al lado, o divide la pantalla y mira las dos a la vez. Lo que escribes es exactamente lo que se guarda: ningún formato propietario entre tú y tus palabras.',
      },
      diagrams: {
        title: 'Diagramas desde texto plano',
        body: 'Escribe un bloque mermaid y míralo convertirse en un diagrama de flujo, de secuencia, una máquina de estados, un gantt, un pastel o un mapa mental. Haz clic en cualquier diagrama para abrirlo a pantalla completa y acercarte. Se dibuja dentro de la app: sin navegador, sin exportar, sin cuenta en un servicio de diagramas.',
      },
      links: {
        title: 'Notas que enlazan a notas',
        body: 'Escribe @ y elige una nota para insertar un enlace en tu texto. Síguelo con un clic y tus ideas empiezan a tomar forma en vez de acumularse.',
      },
      graph: {
        title: 'El grafo de todo',
        body: 'Cada enlace dibuja una arista. Abre el grafo para ver tu biblioteca entera, o activa el panel junto al editor para ver solo con qué conecta la nota que tienes delante. Arrastra las notas, enfoca una para atenuar el resto, haz clic para abrirla.',
      },
      daily: {
        title: 'Una nota para cada día',
        body: 'La nota de hoy te espera al abrir la app, con título y lista. Recorre el mes entero en un calendario y encuentra el día que buscas.',
      },
      search: {
        title: 'Una búsqueda, todo',
        body: 'Busca una vez y alcanza tus notas y tus archivos Markdown juntos, cada resultado etiquetado y abierto donde vive. Sin tener que recordar dónde lo guardaste.',
      },
      folders: {
        title: 'Carpetas que anidan',
        body: 'Agrupa notas en proyectos con color, anídalos tan profundo como haga falta y filtra la barra lateral hasta la rama que te importa.',
      },
      tiling: {
        title: 'Varias notas a la vez',
        body: 'Divide la ventana en una cuadrícula y trabaja en varias notas lado a lado. Cada panel mantiene su barra de herramientas, su vista previa y su autoguardado, así redactar una nota a partir de otras tres deja de significar cambiar de pestaña sin parar.',
      },
      focus: {
        title: 'Tiempo de enfoque, medido',
        body: 'Inicia un temporizador sobre un proyecto y mira cómo suma la semana. Las estadísticas de escritura cuentan la racha por los días que realmente escribiste, no por los días que abriste la app.',
      },
      export: {
        title: 'Tuyas para llevarte',
        body: 'Exporta la biblioteca entera a una carpeta de archivos .md, con carpetas incluidas, o guarda una sola nota donde quieras. Importa una carpeta de vuelta con la misma facilidad. Tus notas sobreviven a la app.',
      },
      sync: {
        title: 'Sincroniza si quieres',
        body: 'Inicia sesión y tus notas te siguen entre dispositivos. Sáltatelo y todo se queda en tu máquina, en una base de datos local. La decisión es tuya, y es reversible.',
      },
      personalise: {
        title: 'Hazla tuya',
        body: 'Trece colores de acento, tu propio fondo de pantalla o un video en bucle detrás del cristal, siete tipografías y un tamaño de texto que no te estorba. El acento incluso se adapta a tu fondo.',
      },
    },
  },

  graph: {
    eyebrow: 'Grafo',
    heading: 'Mira la forma de lo que sabes',
    body: 'Cada enlace que creas dibuja una arista. Las notas a las que vuelves una y otra vez crecen más grandes y más brillantes que las que escribiste una sola vez — así, la estructura que llevas construyendo sin darte cuenta se vuelve algo que puedes mirar.',
    points: [
      'Escribe @ en cualquier punto de una nota y elige otra para enlazarlas.',
      'Abre el grafo para ver la biblioteca entera, o activa el panel junto al editor para ver solo lo que toca esta nota.',
      'Arrastra una nota para moverla, haz clic para enfocarla y atenuar lo demás, y clic de nuevo para abrirla.',
    ],
    svgTitle: 'Un grafo de enlaces de NoteX',
    svgDesc:
      'Once notas dibujadas como círculos unidos por líneas curvas. Una nota central titulada Investigación es la más grande y conecta con Ideas, Lecturas, Notas diarias, Proyectos y Repaso semanal; estas a su vez enlazan con notas más pequeñas, de modo que las más enlazadas son las más grandes y brillantes.',
    nodeLabels: {
      research: 'Investigación',
      ideas: 'Ideas',
      reading: 'Lecturas',
      daily: 'Notas diarias',
      projects: 'Proyectos',
      weekly: 'Repaso semanal',
    },
  },

  tour: {
    heading: 'Un recorrido',
    body: 'Seis pantallas, seis cosas que hace bien.',
    shots: {
      home: {
        eyebrow: 'Inicio',
        title: 'Abre a un espacio, no a un formulario',
        body: 'La nota de hoy, tu racha de escritura, lo último que editaste y lo que sigue pendiente — todo sobre el fondo que elegiste. Todo a un clic, nada exigiendo atención.',
        alt: 'Pantalla de inicio de NoteX mostrando la nota diaria, el total de notas, un gráfico de racha de escritura y recordatorios pendientes sobre un fondo a pantalla completa',
      },
      editor: {
        eyebrow: 'Editor',
        title: 'Fuente a la izquierda, resultado a la derecha',
        body: 'Markdown completo: encabezados, listas de tareas, tablas, notas al pie y bloques de código con resaltado de sintaxis. Divide la vista para ver ambas, o pulsa Cmd/Ctrl+E para alternar.',
        alt: 'El editor de NoteX en vista dividida, Markdown en crudo a la izquierda y el documento renderizado a la derecha, con una barra de formato arriba',
      },
      calendar: {
        eyebrow: 'Calendario',
        title: 'Encuentra el día, encuentra la nota',
        body: 'Cada nota diaria aterriza en el calendario. Los puntos marcan los días que escribiste, así un mes de trabajo se lee de un vistazo y cualquier día queda a un clic.',
        alt: 'Vista de calendario mensual en NoteX con marcas en los días que tienen notas, y las notas del día seleccionado listadas al lado',
      },
      timer: {
        eyebrow: 'Temporizador',
        title: 'Mide en qué estás trabajando',
        body: 'Inicia un temporizador sobre un proyecto, déjalo correr mientras escribes y mira cómo se acumula la semana. Tus sesiones de enfoque viven en la misma app que el trabajo.',
        alt: 'El temporizador de enfoque de NoteX con un campo de tarea, selector de proyecto, reloj en marcha y el total registrado de esta semana',
      },
      tiling: {
        eyebrow: 'Mosaico',
        title: 'Cuatro notas, una pantalla',
        body: 'Divide la ventana en una cuadrícula y edita varias notas lado a lado. Cada panel mantiene su barra de herramientas, su vista previa y su autoguardado — útil cuando redactas una nota a partir de otras tres.',
        alt: 'NoteX en modo mosaico con cuatro notas Markdown abiertas en una cuadrícula de dos por dos, cada una con su barra de herramientas y su cursor',
      },
      settings: {
        eyebrow: 'Personaliza',
        title: 'Haz de ella un lugar donde quieras estar',
        body: 'Trece colores de acento que pueden adaptarse a tu fondo, tu propia imagen o un video en bucle detrás del cristal, siete tipografías y un tamaño de texto ajustado a tus ojos.',
        alt: 'Ajustes de NoteX mostrando muestras de color de acento, fondos de tema, colores de iconos de la barra lateral, selector de video de fondo y lista de tipografías',
      },
    },
  },

  download: {
    heading: 'Empieza a escribir hoy',
    body: 'Gratis, de código abierto e instalada en un minuto. Sin cuenta, sin prueba, sin nada que cancelar después.',
    cta: 'Descargar',
    platforms: {
      macos: { platform: 'macOS', note: 'Apple Silicon e Intel' },
      windows: { platform: 'Windows', note: 'Instalador, 64 bits' },
      linux: { platform: 'Linux', note: 'Debian y Ubuntu' },
    },
    versionLine: (version) => `Versión ${version} · Licencia MIT ·`,
    allReleases: 'Todas las versiones y cambios',
    firstRun: {
      summary: 'Tu Mac o PC te advierte la primera vez que la abres — esta es la razón',
      body: 'Las versiones no están firmadas con un certificado de desarrollador. Tanto Apple como Microsoft cobran una suscripción anual por uno, y NoteX es gratis, así que los binarios salen sin firmar y el sistema operativo dice que no puede responder por ellos. Es una afirmación sobre un recibo, no sobre el código — que puedes leer, y compilar tú mismo, por completo.',
      says: 'Dice',
      macos: {
        // What a Spanish-language macOS actually puts on screen — not a
        // translation of the English dialog.
        warning: '«Apple no puede verificar que "NoteX.app" esté libre de malware».',
        steps: [
          'Abre Ajustes del Sistema → Privacidad y Seguridad.',
          'Baja hasta la sección Seguridad — ahí aparecerá NoteX como bloqueada.',
          'Pulsa Abrir de todos modos y confirma.',
        ],
        note: 'En macOS 15 y posteriores, hacer clic derecho sobre la app y elegir Abrir ya no funciona: Apple eliminó esa vía. El panel de Privacidad y Seguridad es el camino.',
      },
      windows: {
        warning: '«Windows protegió su PC».',
        steps: ['Pulsa Más información.', 'Pulsa Ejecutar de todas formas.'],
      },
    },
  },

  faq: {
    heading: 'Preguntas',
    items: [
      {
        q: '¿NoteX es gratis?',
        a: 'Sí. NoteX es gratuita y de código abierto bajo licencia MIT. No requiere cuenta, no tiene suscripción ni versión de pago. Si se gana un lugar en tu día, hay un enlace de Invítame un café en el pie de página — totalmente opcional, y no se retiene nada sin él.',
      },
      {
        q: '¿Dónde se guardan mis notas?',
        a: 'En una base de datos SQLite local, en tu propia máquina. Si inicias sesión, las notas también se sincronizan con tu proyecto de Supabase para que te sigan entre dispositivos — pero iniciar sesión es totalmente opcional.',
      },
      {
        q: '¿Puedo sacar mis notas?',
        a: 'Cuando quieras. Exporta la biblioteca entera a una carpeta de archivos Markdown, conservando tu estructura de carpetas, o guarda una sola nota donde prefieras. Las notas ya se guardan como Markdown, así que nada se convierte al salir.',
      },
      {
        q: '¿Por qué mi Mac dice que NoteX no se puede verificar?',
        a: 'Porque el binario no está firmado con un certificado de desarrollador de pago, así que macOS no puede comprobar un recibo — no es un hallazgo sobre el código. Para abrirla: Ajustes del Sistema → Privacidad y Seguridad → baja hasta Seguridad → Abrir de todos modos. Ten en cuenta que en macOS 15 y posteriores, hacer clic derecho y elegir Abrir ya no funciona; Apple eliminó esa vía. Windows muestra un aviso equivalente, "Windows protegió su PC", donde Más información → Ejecutar de todas formas lo resuelve. El código fuente completo es público si prefieres leerlo o compilarlo tú mismo.',
      },
      {
        q: '¿Qué Markdown soporta?',
        a: 'GitHub Flavored Markdown, renderizado de forma nativa en la app: encabezados, tablas, listas de tareas, notas al pie, tachado, enlaces automáticos, avisos destacados (> [!NOTE] y similares), atajos de emoji y bloques de código con resaltado de sintaxis. Un bloque ```mermaid se dibuja como diagrama — de flujo, de secuencia, máquinas de estados, gantt, pastel y mapas mentales — y puedes abrirlo a pantalla completa para acercarte. Nada se convierte ni se sube: el archivo en disco sigue siendo el Markdown que escribiste.',
      },
      {
        q: '¿En qué plataformas funciona?',
        a: 'Windows, macOS y Linux. Cada versión publica las tres, compiladas desde el mismo código.',
      },
      {
        q: '¿Funciona sin conexión?',
        a: 'Por completo. NoteX es una app de escritorio local-first: todo funciona sin conexión, y la sincronización se pone al día cuando vuelves a estar en línea.',
      },
    ],
  },

  footer: {
    support: 'Invítame un café',
    legal: (year, author) => `© ${year} ${author} · Licencia MIT · Hecha con Flutter`,
    socialLabel: (author, network) => `${author} en ${network}`,
  },
};
