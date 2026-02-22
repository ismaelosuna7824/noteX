/// Port (interface) for monitoring network connectivity.
///
/// Domain depends on this contract — infrastructure provides the adapter.
abstract class ConnectivityService {
  /// Whether the device currently has internet access.
  bool get isOnline;

  /// Stream that emits whenever connectivity changes.
  Stream<bool> get onConnectivityChanged;
}
