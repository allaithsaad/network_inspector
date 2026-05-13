## 2.0.0

**Breaking change:** `navigatorKey` is now a required parameter on `NetworkInspectorOverlay`.
Pass your app's `GlobalKey<NavigatorState>` (or `Get.key` for GetX).

### New
* Share button in the detail screen — shares the full request/response as plain text.
* Copy button on the summary section (URL · method · status · duration · time).
* Example app under `example/` using the JSONPlaceholder public API.

### Changed
* `navigatorKey` promoted from optional to required — eliminates a class of
  navigation errors when the overlay sits above the Navigator.

---

## 0.1.0

* Initial release.
* `NetworkInspectorOverlay` — draggable floating button overlay.
* `NetworkLogger` — singleton ChangeNotifier log store.
* `NetworkInspectorHttpClient` — automatic http package adapter.
* Manual `logRequest` API for any HTTP client.
* Debug-only: zero overhead in release builds.
