# THOR Backfire Tool (Android nativo)

App Android mínima para conectar directamente por BLE al módulo THOR, leer la regla `0x0021` y probar los valores 3 y 7 sin modificar la app THOR oficial.

## Compilar
- Android Studio: abrir esta carpeta y ejecutar **Build > Build APK(s)**.
- GitHub Actions: subir a un repositorio y ejecutar el workflow **Build APK**. El APK aparece como artefacto `THOR-Backfire-Tool-APK`.

## Uso
1. Encender el coche/THOR.
2. Cerrar completamente la app THOR oficial.
3. Abrir esta app, conceder permisos Bluetooth y pulsar **Conectar al THOR**.
4. Verificar primero que lee `Valor actual: 3`.
5. Solo después probar **Aplicar 7**. La app vuelve a leer la regla y muestra el valor realmente conservado por THOR.

## Nota
No escribe en la ECU del coche. Solo usa BLE para hablar con el módulo THOR. Es una herramienta experimental basada en el protocolo observado en la captura del dispositivo del usuario.
