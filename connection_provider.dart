<!-- Добавь эти ключи в ios/Runner/Info.plist (внутри корневого <dict>) -->

<key>NSBluetoothAlwaysUsageDescription</key>
<string>Приложению нужен Bluetooth для связи с OBD-адаптером ELM327</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>Приложению нужен Bluetooth для связи с OBD-адаптером ELM327</string>

<key>NSLocalNetworkUsageDescription</key>
<string>Доступ к локальной сети нужен для подключения к Wi-Fi OBD-адаптеру</string>

<!-- ВАЖНО для Wi-Fi адаптеров: разрешаем нешифрованное TCP-соединение
     с локальным адресом адаптера (192.168.0.10) -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
