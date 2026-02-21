# 🧠 APP DE NOTAS FLUTTER DESKTOP

## Arquitectura Hexagonal + DDD + Offline First + Google Auth + AutoSave

------------------------------------------------------------------------

## 🎯 Objetivo

Quiero que actúes como un arquitecto senior especializado en Flutter Desktop, Arquitectura Hexagonal y Domain-Driven Design (DDD).

Necesito desarrollar una aplicación de notas exclusivamente para escritorio (Windows, Linux y macOS) usando Flutter.

La app debe cumplir estrictamente arquitectura Hexagonal (Ports & Adapters) y DDD. No quiero mezcla de responsabilidades.

La aplicación debe seguir estrictamente:

-   Arquitectura Hexagonal (Ports & Adapters)
-   Domain-Driven Design (DDD)
-   Principios SOLID
-   Separación estricta de capas
-   Offline-first real

------------------------------------------------------------------------

# 🏗 Arquitectura Obligatoria

Estructura requerida:

lib/ ├── domain/ │ ├── entities/ │ ├── value_objects/ │ ├──
repositories/ │ ├── services/ │ ├── events/ │ ├── application/ │ ├──
use_cases/ │ ├── services/ │ ├── infrastructure/ │ ├── local/ │ ├──
firebase/ │ ├── api/ │ ├── auth/ │ ├── presentation/ │ ├── pages/ │ ├──
widgets/ │ ├── state/ │ └── main.dart

El dominio NO debe depender de Flutter, Firebase ni librerías externas.

------------------------------------------------------------------------

# 🧱 Dominio

Entidad principal: Note

Campos:

-   id
-   title
-   content
-   createdAt
-   updatedAt
-   syncStatus
-   backgroundImage
-   themeId

Reglas de negocio:

-   Cada día que el usuario abre la app se crea automáticamente una
    nueva nota si no existe una para ese día.
-   La app debe funcionar completamente offline.
-   Si el usuario inicia sesión, se activa sincronización bidireccional.
-   Resolución de conflictos basada en updatedAt (Last Write Wins).
-   El dominio debe ser puro.

------------------------------------------------------------------------

# 💾 Persistencia (Offline First)

-   Almacenamiento local usando Drift o Hive.
-   Sin autenticación, la app funciona en modo local-only.
-   Si el usuario inicia sesión con Google:
    -   Se activa sincronización automática.
    -   Se asocian notas al UID del usuario.
    -   Si inicia sesión en otro dispositivo, recupera sus notas.
-   Sincronización automática en segundo plano.
-   Implementar SyncEngine desacoplado.

------------------------------------------------------------------------

# 🔐 Autenticación

-   Único método: Google.
-   Implementación usando Firebase Authentication.
-   No deben existir otros métodos de login.
-   Si el usuario cierra sesión:
    -   La app vuelve a modo local-only.
    -   Las notas locales no se eliminan.

------------------------------------------------------------------------

# 💾 Auto-Guardado Inteligente

La app NO debe tener botón de guardar.

Debe implementar:

-   Guardado automático cuando el usuario deja de escribir.
-   Debounce inteligente (800ms--1000ms).
-   No guardar en cada tecla.
-   Al guardar:
    -   Se actualiza updatedAt.
    -   Se marca como pendingSync.
    -   Se dispara sincronización si el usuario está autenticado.

El AutoSave debe vivir en application layer.

------------------------------------------------------------------------

# ✏ Editor de Texto

-   Editor enriquecido (ej: flutter_quill).
-   Buen rendimiento.
-   Guardado automático integrado.
-   Arquitectura desacoplada.

------------------------------------------------------------------------

# 🎨 Diseño

-   Debe respetar exactamente el diseño proporcionado.
-   Permitir cambio dinámico de tema, el color del teme se debe de adaptar al la imagen del fondo.
-   Permitir cambio dinámico de imagen de fondo.
-   Permitir cambio dinámico de fuente.
-   Permitir el cambio de imagen de fondo al usuario.
-   El layout base no debe romperse.
-   ThemeManager desacoplado del dominio.
-   No debe haber un solo archivo de estilos.
-   No debe haber un solo archivo de temas.
-   No debe haber un solo archivo de widgets.
-   No debe haber un solo archivo de eventos.

------------------------------------------------------------------------

# 📅 Visualización

Dos modos:

1.  Vista lista
2.  Vista calendario

Debe existir un ViewMode enum.

------------------------------------------------------------------------

# 🔄 API Externa Diaria

Cada día la app debe:

-   Llamar a una API externa (implementada por el backend).
-   Enviar resumen del contenido de la nota.
-   Recibir un nuevo título generado automáticamente.
-   Actualizar el título en tiempo real.
-   Guardar automáticamente el nuevo título.

Debe incluir:

-   ApiAdapter en infraestructura.
-   Caso de uso en application.
-   Actualización reactiva.


------------------------------------------------------------------------

# ⚙ Requisitos Adicionales

-   Inyección de dependencias (get_it o similar).
-   Logging estructurado.
-   Manejo centralizado de errores.
-   Configuración por entorno.
-   Soporte multiplataforma desktop.
-   README explicando cómo extender la app.

------------------------------------------------------------------------

# 📦 Entrega Esperada

1.  Estructura completa del proyecto.
2.  Código base funcional.
3.  Implementación del SyncEngine.
4.  Implementación del AutoSaveService.
5.  Implementación de Google Auth con Firebase.
6.  Ejemplo completo de un caso de uso.
7.  Explicación arquitectónica.

No se aceptan ejemplos simplificados. Debe ser base profesional lista
para crecer.
