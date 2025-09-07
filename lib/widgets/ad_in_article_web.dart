import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'dart:ui_web' as ui;
import 'package:web/web.dart' as web;

import '../adsense_ids.dart';

/// Google AdSense In-Article (fluid) for Flutter Web.
class AdInArticleWeb extends StatefulWidget {
  final String adSlot;
  final double height;
  final EdgeInsetsGeometry? margin;

  const AdInArticleWeb({
    super.key,
    required this.adSlot,
    this.height = 280,
    this.margin,
  });

  @override
  State<AdInArticleWeb> createState() => _AdInArticleWebState();
}

class _AdInArticleWebState extends State<AdInArticleWeb> {
  String? _viewType;
  web.HTMLDivElement? _root;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;

    _viewType = 'adsbygoogle-ia-${DateTime.now().microsecondsSinceEpoch}';

    // <ins class="adsbygoogle" data-ad-format="fluid" data-ad-layout="in-article">
    final ins = web.document.createElement('ins') as web.HTMLElement;
    ins.className = 'adsbygoogle';
    ins.style.display = 'block';
    ins.style.textAlign = 'center';
    ins.setAttribute('data-ad-client', kAdClient);
    ins.setAttribute('data-ad-slot', widget.adSlot);
    ins.setAttribute('data-ad-format', 'fluid');
    ins.setAttribute('data-ad-layout', 'in-article');

    _root = web.HTMLDivElement()..style.width = '100%';
    _root!.append(ins);

    ui.platformViewRegistry.registerViewFactory(_viewType!, (int _) => _root!);

    final script = web.document.createElement('script') as web.HTMLScriptElement;
    script.text = '(adsbygoogle = window.adsbygoogle || []).push({});';
    _root!.append(script);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return Container(
      margin: widget.margin ?? const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: HtmlElementView(viewType: _viewType!),
      ),
    );
  }
}
