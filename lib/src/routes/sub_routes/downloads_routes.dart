part of '../router_config.dart';

class DownloadsBranch extends StatefulShellBranchData {
  const DownloadsBranch();
}

class DownloadsRoute extends GoRouteData with $DownloadsRoute {
  const DownloadsRoute();
  @override
  Widget build(context, state) {
    final query = state.uri.queryParameters;
    final onDevice = query['tab'] == 'device';
    return DownloadsScreen(
      key: query['open'] == null ? null : ValueKey(query['open']),
      openOnDevice: onDevice,
    );
  }
}
