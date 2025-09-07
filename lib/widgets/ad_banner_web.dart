import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'dart:ui_web' as ui;
import 'package:web/web.dart' as web;

import '../adsense_ids.dart';

/// Responsive AdSense banner for Flutter Web.
/// Requires the AdSense script in web/index.html with your client id.
class AdBannerWeb extends StatefulWidget {
  /// Your AdSense slot id (numbers only).
  final String adSlot;

  /// Height hint for the container (ad is responsive).
  final double height;

  /// Optional margin.
  final EdgeInsetsGeometry? margin;

  const AdBannerWeb({
    super.key,
    required this.adSlot,
    this.height = 100,
    this.margin,
  });

  @override
  State<AdBannerWeb> createState() => _AdBannerWebState();
}

class _AdBannerWebState extends State<AdBannerWeb> {
  String? _viewType;
  web.HTMLDivElement? _root;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;

    _viewType = 'adsbygoogle-${DateTime.now().microsecondsSinceEpoch}';

    // <ins class="adsbygoogle" ... />
    final ins = web.document.createElement('ins') as web.HTMLElement;
    ins.className = 'adsbygoogle';
    ins.style.display = 'block';
    ins.style.textAlign = 'center';
    ins.setAttribute('data-ad-client', kAdClient);
    ins.setAttribute('data-ad-slot', widget.adSlot);
    ins.setAttribute('data-ad-format', 'auto');
    ins.setAttribute('data-full-width-responsive', 'true');

    _root = web.HTMLDivElement();
    _root!.style.width = '100%';
    _root!.append(ins);

    // Register the platform view
    ui.platformViewRegistry.registerViewFactory(_viewType!, (int _) => _root!);

    // Trigger adsbygoogle.push({})
    final script = web.document.createElement('script') as web.HTMLScriptElement;
    script.text = '(adsbygoogle = window.adsbygoogle || []).push({});';
    _root!.append(script);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return Container(
      margin: widget.margin ?? const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: HtmlElementView(viewType: _viewType!),
      ),
    );
  }
}
