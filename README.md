# 🚀 KAMIKAZE PHONE

## ¡El juego más extremo para tu celular!

**Kamikaze Phone** es un juego innovador que utiliza los sensores de tu teléfono móvil para crear una experiencia de juego única y emocionante. Utilizando el acelerómetro y giroscopio, el juego detecta lanzamientos y flips de tu dispositivo para generar puntuaciones basadas en la física real.

## 🎮 Modos de Juego

### 🚀 Kamikaze Normal
- **Objetivo**: Lanza tu teléfono hacia arriba lo más alto posible
- **Puntuación**: Basada en la aceleración máxima y duración del lanzamiento
- **Mecánica**: El juego detecta automáticamente cuando lanzas el teléfono usando el acelerómetro
- **Riesgo**: ¡Asegúrate de atraparlo!

### 🔄 Kamikaze Flip
- **Objetivo**: Realiza flips y giros con tu teléfono
- **Puntuación**: Basada en la velocidad de rotación y tipos de flip
- **Tipos de Flip**:
  - **Frontside Flip / Backside Flip**: Rotación en eje X
  - **Kickflip / Heelflip**: Rotación en eje Y
  - **360 Spin / Reverse 360**: Rotación en eje Z
- **Mecánica**: El giroscopio detecta automáticamente los diferentes tipos de giros

## 🔧 Características Técnicas

### Sensores Utilizados
- **Acelerómetro**: Detecta la aceleración del dispositivo en los 3 ejes
- **Giroscopio**: Mide la velocidad de rotación en los 3 ejes
- **Orientación**: Proporciona información adicional sobre la posición del dispositivo

### Detección Inteligente
- **Lanzamiento**: Se detecta cuando la aceleración supera 15 m/s²
- **Caída Libre**: Se identifica cuando la aceleración cae por debajo de 5 m/s²
- **Flips**: Se detectan cuando la velocidad de rotación supera 200°/s

### Modo Debug
- **Revisa antihiroscopio**: Modo de depuración completo
- **Logs en tiempo real**: Muestra toda la actividad de sensores
- **Datos de sensores**: Visualización de acelerómetro, giroscopio y orientación
- **Estado de permisos**: Verificación de acceso a sensores

## 📱 Compatibilidad

### Dispositivos Compatibles
- **iOS 13+**: Requiere solicitud de permisos explícita
- **Android 4.4+**: Permisos automáticos para sensores
- **Navegadores**: Chrome, Safari, Firefox, Edge (versiones recientes)

### Permisos Necesarios
- **DeviceMotionEvent**: Para acceder al acelerómetro y giroscopio
- **DeviceOrientationEvent**: Para acceder a la orientación del dispositivo

## 🎯 Sistema de Puntuación

### Kamikaze Normal
```
Puntos = (Aceleración Máxima × Duración del Lanzamiento) ÷ 100
```

### Kamikaze Flip
```
Puntos = Velocidad de Rotación ÷ 10
```

## 🏆 Características de Juego

- **Sistema de Records**: Almacena tu mejor puntuación localmente
- **Logs de Debug**: Visualiza toda la actividad en tiempo real
- **Detección Precisa**: Algoritmos optimizados para máxima precisión
- **Interfaz Profesional**: Diseño moderno con efectos visuales
- **Responsive**: Funciona en todos los tamaños de pantalla

## 🚀 Cómo Empezar

1. **Abrir el juego** en tu dispositivo móvil
2. **Otorgar permisos** cuando se soliciten
3. **Seleccionar modo** de juego en la pantalla principal
4. **¡Jugar!** - Lanza o gira tu teléfono según el modo

## ⚠️ Advertencias de Seguridad

- **¡Ten cuidado!** Asegúrate de tener un buen agarre
- **Espacio libre**: Juega en áreas abiertas sin obstáculos
- **Superficie blanda**: Considera jugar sobre una cama o sofá
- **Protección**: Usa una funda resistente para tu teléfono
- **Responsabilidad**: El juego no se hace responsable por daños

## 🛠️ Desarrollo

### Tecnologías Utilizadas
- **Next.js 14**: Framework React para desarrollo web
- **TypeScript**: Tipado estático para mayor robustez
- **Tailwind CSS**: Framework de estilos utilitarios
- **Web APIs**: DeviceMotionEvent, DeviceOrientationEvent

### Instalación para Desarrollo
```bash
# Clonar el repositorio
git clone [url-del-repositorio]

# Instalar dependencias
npm install

# Ejecutar en modo desarrollo
npm run dev

# Compilar para producción
npm run build
```

## 🎨 Características Visuales

- **Gradientes dinámicos**: Fondos animados con colores vibrantes
- **Efectos de neón**: Texto y bordes con efectos luminosos
- **Animaciones suaves**: Transiciones y efectos de hover
- **Scroll personalizado**: Barras de desplazamiento estilizadas
- **Tipografía profesional**: Fuentes optimizadas para dispositivos móviles

## 📊 Métricas de Debug

El modo debug proporciona información detallada sobre:
- Estado de permisos de sensores
- Datos en tiempo real del acelerómetro (X, Y, Z)
- Datos en tiempo real del giroscopio (X, Y, Z)
- Orientación del dispositivo (Alpha, Beta, Gamma)
- Detección de lanzamientos y flips
- Historial de logs con timestamps

## 🔮 Próximas Características

- **Multiplayer**: Competir con otros jugadores
- **Ranking Global**: Leaderboards mundiales
- **Más modos**: Nuevos tipos de juego y desafíos
- **Logros**: Sistema de achievements
- **Grabación**: Replay de tus mejores jugadas

---

**¡Desarrollado con ❤️ para los amantes de los juegos extremos!**

*Recuerda: La seguridad es lo primero. Juega responsablemente.*