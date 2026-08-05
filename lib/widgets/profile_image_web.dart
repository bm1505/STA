import 'package:flutter/material.dart';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'dart:js_interop';

// Registry ya kuzuia re-registration errors
final Set<String> _registeredViews = {};

Widget buildWebImage({
  required String url,
  double radius = 0,
  BoxFit fit = BoxFit.cover,
  Widget? placeholder,
}) {
  // 1. Tengeneza ID thabiti (Stable ID) bila timestamp
  // Hii inahakikisha View haifi kila wakati picha inapojichora
  String stableId = url;
  if (url.contains('userId=')) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final uid = uri.queryParameters['userId'] ?? 'unknown';
      final type = uri.queryParameters['type'] ?? 'unknown';
      stableId = 'view-$uid-$type';
    }
  } else {
    stableId = 'view-${url.hashCode}';
  }

  if (!_registeredViews.contains(stableId)) {
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
      stableId,
      (int viewId) {
        final img = web.HTMLImageElement()
          ..src = url
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = fit == BoxFit.contain ? 'contain' : 'cover';
        
        img.onerror = (web.Event e) {
           print('❌ Web Image Load Failed: $url');
        }.toJS;

        return img;
      },
    );
    _registeredViews.add(stableId);
  }

  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox.expand(
      child: HtmlElementView(
        key: ValueKey(stableId), 
        viewType: stableId,
      ),
    ),
  );
}
