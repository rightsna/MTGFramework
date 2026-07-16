/// The device classes a project authors screenshots for. Each [code] is the
/// on-disk folder name nested ABOVE the locale (`screenshots/<device>/<locale>/`)
/// and carries the default App Store export size for that device, so a new shot
/// starts at the right dimensions.
class StoreDevice {
  final String code; // folder name
  final String ko; // Korean label
  final String en; // English label
  final int exportW; // default export width (px)
  final int exportH; // default export height (px)
  const StoreDevice(this.code, this.ko, this.en, this.exportW, this.exportH);
}

/// Supported device classes with their default App Store screenshot sizes:
/// iPhone 6.5" is 1242×2688 and iPad 12.9" is 2048×2732 (Apple rejects anything
/// else for these slots); Mac accepts 1280×800 / 1440×900 / 2560×1600 /
/// 2880×1800 — we default to 2880×1800 (16:10 Retina).
const List<StoreDevice> kStoreDevices = [
  StoreDevice('mobile', '모바일', 'Mobile', 1242, 2688),
  StoreDevice('ipad', '패드', 'Pad', 2048, 2732),
  StoreDevice('desktop', '데스크탑', 'Desktop', 2880, 1800),
];

/// Where legacy (device-less) screenshots are migrated to.
const String kDefaultDevice = 'mobile';

/// Known device folder names — used to tell device folders apart from locale /
/// document folders during migration.
final Set<String> kKnownDeviceCodes = {for (final d in kStoreDevices) d.code};

StoreDevice? storeDeviceByCode(String code) {
  for (final d in kStoreDevices) {
    if (d.code == code) return d;
  }
  return null;
}

String storeDeviceLabel(String code, {required bool english}) {
  final d = storeDeviceByCode(code);
  if (d == null) return code;
  return english ? d.en : d.ko;
}
