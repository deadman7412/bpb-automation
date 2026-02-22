enum UpdateMode { cloudflareApi, panelApi }

extension UpdateModeX on UpdateMode {
  String get storageValue {
    switch (this) {
      case UpdateMode.cloudflareApi:
        return 'cloudflare_api';
      case UpdateMode.panelApi:
        return 'panel_api';
    }
  }

  String get displayName {
    switch (this) {
      case UpdateMode.cloudflareApi:
        return 'Cloudflare API';
      case UpdateMode.panelApi:
        return 'Panel API';
    }
  }

  static UpdateMode fromStorageValue(String? value) {
    switch (value) {
      case 'panel_api':
        return UpdateMode.panelApi;
      case 'cloudflare_api':
        return UpdateMode.cloudflareApi;
      default:
        return UpdateMode.cloudflareApi;
    }
  }
}
