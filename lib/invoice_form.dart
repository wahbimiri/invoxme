import 'package:flutter/foundation.dart' show kIsWeb;
import 'widgets/ad_banner_web.dart';
import 'widgets/ad_in_article_web.dart';
import 'adsense_ids.dart';

import 'dart:convert';
import 'dart:typed_data';
import 'package:web/web.dart' as web; // localStorage & download on Web
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import 'package:csv/csv.dart' as csv; // CSV

class InvoiceForm extends StatefulWidget {
  final String Function(String) t;
  const InvoiceForm({super.key, required this.t});

  @override
  State<InvoiceForm> createState() => _InvoiceFormState();
}

class _InvoiceFormState extends State<InvoiceForm> {
  static const _kDraftKey = 'invoxi_draft_v1';
  static const _kCounterKey = 'invoxi_counter_v1';

  // Header
  final _sellerCtrl = TextEditingController();
  final _buyerCtrl = TextEditingController();
  final _invoiceNoCtrl = TextEditingController(text: 'INV-001');
  DateTime _invoiceDate = DateTime.now();

  // Branding
  final _brandCtrl = TextEditingController(text: 'Invoxi');
  final _docTitleCtrl = TextEditingController(text: 'Invoice');

  // Settings
  final _currencyCtrl = TextEditingController(text: 'QAR');
  final _taxRateCtrl = TextEditingController(text: '0'); // %
  final _discountCtrl = TextEditingController(text: '0'); // %
  final _deliveryCtrl = TextEditingController(text: '0'); // flat amount

  // Payment (Optional & flexible)
  String _paymentStatus = 'unpaid'; // unpaid | paid | pay_later | cod
  final _paymentStatusCustomCtrl = TextEditingController(); // free text overrides
  final _paymentMethodCtrl = TextEditingController(); // free text
  final _paymentTermsCtrl = TextEditingController(); // free text
  DateTime? _dueDate; // optional

  // Paper options
  String _pageSize = 'A4'; // 'A4' | 'Letter'
  bool _landscape = false;

  // Company profile fields
  final _addrCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  final _ibanCtrl = TextEditingController();
  final _footerNoteCtrl = TextEditingController();

  // Logo + Signature
  Uint8List? _logoBytes;
  Uint8List? _signatureBytes;

  // Items
  final List<_ItemCtrls> _items = [];

  // ===== Auto-numbering =====
  final _invPrefixCtrl = TextEditingController(text: 'INV-');
  final _invPadCtrl = TextEditingController(text: '3');

  String _formatInvNo({
    required String prefix,
    required int year,
    required int n,
    required int pad,
  }) {
    final numStr = n.toString().padLeft(pad, '0');
    return '$prefix$year-$numStr';
  }

  void _nextInvoiceNumber() {
    final prefix = _invPrefixCtrl.text;
    final pad = int.tryParse(_invPadCtrl.text) ?? 3;
    final nowY = DateTime.now().year;

    int year = nowY;
    int next = 1;

    try {
      final raw = web.window.localStorage.getItem(_kCounterKey);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        year = (m['year'] is int) ? m['year'] as int : nowY;
        next = (m['next'] is int) ? m['next'] as int : 1;
        if (year != nowY) {
          year = nowY;
          next = 1;
        }
      }
    } catch (_) {}

    final newNo = _formatInvNo(prefix: prefix, year: year, n: next, pad: pad);
    setState(() => _invoiceNoCtrl.text = newNo);

    try {
      web.window.localStorage.setItem(
        _kCounterKey,
        jsonEncode({'year': year, 'next': next + 1}),
      );
    } catch (_) {}

    _saveDraft();
  }

  @override
  void initState() {
    super.initState();
    _loadDraftIfAny();
  }

  @override
  void dispose() {
    for (final it in _items) {
      it.dispose();
    }
    _sellerCtrl.dispose();
    _buyerCtrl.dispose();
    _invoiceNoCtrl.dispose();
    _brandCtrl.dispose();
    _docTitleCtrl.dispose();
    _currencyCtrl.dispose();
    _taxRateCtrl.dispose();
    _discountCtrl.dispose();
    _deliveryCtrl.dispose();
    _paymentStatusCustomCtrl.dispose();
    _paymentMethodCtrl.dispose();
    _paymentTermsCtrl.dispose();
    _addrCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _websiteCtrl.dispose();
    _taxIdCtrl.dispose();
    _ibanCtrl.dispose();
    _footerNoteCtrl.dispose();
    _invPrefixCtrl.dispose();
    _invPadCtrl.dispose();
    super.dispose();
  }

  // ---------------- Draft (invoice) ----------------
  void _saveDraft() {
    try {
      web.window.localStorage.setItem(_kDraftKey, jsonEncode(_currentTemplateMap()));
    } catch (_) {}
  }

  void _loadDraftIfAny() {
    try {
      final raw = web.window.localStorage.getItem(_kDraftKey);
      if (raw == null || raw.isEmpty) {
        _addItem();
        return;
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _applyTemplateMap(map);
    } catch (_) {
      _items.clear();
      _addItem();
    }
  }

  // ---------------- Pickers ----------------
  Future<void> _pickLogo() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = res?.files.single.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      setState(() => _logoBytes = bytes);
      _saveDraft();
    }
  }

  void _removeLogo() {
    setState(() => _logoBytes = null);
    _saveDraft();
  }

  Future<void> _pickSignature() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = res?.files.single.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      setState(() => _signatureBytes = bytes);
      _saveDraft();
    }
  }

  void _removeSignature() {
    setState(() => _signatureBytes = null);
    _saveDraft();
  }

  Future<void> _pickDueDate() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () {
                      setState(() => _dueDate = null);
                      Navigator.of(ctx).pop();
                      _saveDraft();
                    },
                    child: Text(widget.t('clear')),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(widget.t('ok')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _dueDate ?? DateTime.now(),
                maximumDate: DateTime(2100),
                onDateTimeChanged: (dt) {
                  _dueDate = dt;
                },
              ),
            ),
          ],
        ),
      ),
    );
    setState(() {});
    _saveDraft();
  }

  // ---------------- Helpers ----------------
  void _addItem() {
    setState(() => _items.add(_ItemCtrls()));
    _saveDraft();
  }

  void _removeItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
      if (_items.isEmpty) _items.add(_ItemCtrls());
    });
    _saveDraft();
  }

  double _parseD(String v) => double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
  int _parseI(String v) => int.tryParse(v) ?? 0;

  // ---------- locale helpers ----------
  String _userLocale(BuildContext ctx) => Localizations.localeOf(ctx).toLanguageTag();
  String _fmtDateL(DateTime d, String locale) => DateFormat.yMMMd(locale).format(d);
  String _fmtCurrencyL(double v, String currency, String locale) =>
      '${NumberFormat.decimalPattern(locale).format(v)} $currency';

  _Totals _computeTotals() {
    double sub = 0;
    for (final it in _items) {
      sub += _parseI(it.qty.text) * _parseD(it.price.text);
    }
    final discountP = _parseD(_discountCtrl.text);
    final delivery = _parseD(_deliveryCtrl.text);
    final taxRate = _parseD(_taxRateCtrl.text);

    final discount = sub * (discountP / 100.0);
    final base = (sub - discount);
    final tax = base * (taxRate / 100.0);
    final total = base + tax + delivery;

    return _Totals(
      subtotal: sub,
      discount: discount,
      delivery: delivery,
      tax: tax,
      total: total,
    );
  }

  Future<void> _showInfo(String msg) async {
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(msg),
        actions: [
          CupertinoDialogAction(
            child: Text(widget.t('ok')),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _cupertinoDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          height: 1,
          color: CupertinoColors.separator.resolveFrom(context),
        ),
      );

  // ---------------- Template (invoice) Export/Import ----------------
  Map<String, dynamic> _currentTemplateMap() {
    return {
      'seller': _sellerCtrl.text,
      'buyer': _buyerCtrl.text,
      'invoiceNo': _invoiceNoCtrl.text,
      'invoiceDate': _invoiceDate.toIso8601String(),
      'brand': _brandCtrl.text,
      'docTitle': _docTitleCtrl.text,
      'currency': _currencyCtrl.text,
      'taxRate': _taxRateCtrl.text,
      'discountPercent': _discountCtrl.text,
      'deliveryCharge': _deliveryCtrl.text,

      // Payments
      'paymentStatus': _paymentStatus,
      'paymentStatusText': _paymentStatusCustomCtrl.text,
      'paymentMethod': _paymentMethodCtrl.text,
      'paymentTerms': _paymentTermsCtrl.text,
      'dueDate': _dueDate?.toIso8601String(),

      // paper
      'pageSize': _pageSize,
      'landscape': _landscape,
      'invPrefix': _invPrefixCtrl.text,
      'invPad': _invPadCtrl.text,

      // profile snapshot
      'address': _addrCtrl.text,
      'phone': _phoneCtrl.text,
      'email': _emailCtrl.text,
      'website': _websiteCtrl.text,
      'taxId': _taxIdCtrl.text,
      'iban': _ibanCtrl.text,
      'footerNote': _footerNoteCtrl.text,

      // media
      'logoB64': _logoBytes == null ? null : base64Encode(_logoBytes!),
      'signatureB64': _signatureBytes == null ? null : base64Encode(_signatureBytes!),

      // items
      'items': _items
          .map((it) => {
                'desc': it.desc.text,
                'qty': it.qty.text,
                'price': it.price.text,
              })
          .toList(),
    };
  }

  void _applyTemplateMap(Map<String, dynamic> map) {
    _sellerCtrl.text = (map['seller'] ?? '').toString();
    _buyerCtrl.text = (map['buyer'] ?? '').toString();
    _invoiceNoCtrl.text = (map['invoiceNo'] ?? 'INV-001').toString();

    final dateStr = (map['invoiceDate'] ?? '').toString();
    if (dateStr.isNotEmpty) {
      _invoiceDate = DateTime.tryParse(dateStr) ?? DateTime.now();
    }

    _brandCtrl.text = (map['brand'] ?? 'Invoxi').toString();
    _docTitleCtrl.text = (map['docTitle'] ?? 'Invoice').toString();
    _currencyCtrl.text = (map['currency'] ?? 'QAR').toString();
    _taxRateCtrl.text = (map['taxRate'] ?? '0').toString();
    _discountCtrl.text = (map['discountPercent'] ?? '0').toString();
    _deliveryCtrl.text = (map['deliveryCharge'] ?? '0').toString();

    // Payments
    _paymentStatus = (map['paymentStatus'] ?? 'unpaid').toString();
    _paymentStatusCustomCtrl.text = (map['paymentStatusText'] ?? '').toString();
    _paymentMethodCtrl.text = (map['paymentMethod'] ?? '').toString();
    _paymentTermsCtrl.text = (map['paymentTerms'] ?? '').toString();
    final dueStr = (map['dueDate'] ?? '').toString();
    _dueDate = dueStr.isEmpty ? null : (DateTime.tryParse(dueStr) ?? _dueDate);

    // paper
    _pageSize = (map['pageSize'] ?? 'A4').toString();
    _landscape = (map['landscape'] ?? false) == true;
    _invPrefixCtrl.text = (map['invPrefix'] ?? _invPrefixCtrl.text).toString();
    _invPadCtrl.text = (map['invPad'] ?? _invPadCtrl.text).toString();

    // profile bits too
    _applyProfileMap(map, callSetState: false);

    // logo
    final b64 = map['logoB64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      try {
        _logoBytes = base64Decode(b64);
      } catch (_) {
        _logoBytes = null;
      }
    } else {
      _logoBytes = null;
    }

    // signature
    final s64 = map['signatureB64']?.toString();
    if (s64 != null && s64.isNotEmpty) {
      try {
        _signatureBytes = base64Decode(s64);
      } catch (_) {
        _signatureBytes = null;
      }
    } else {
      _signatureBytes = null;
    }

    for (final e in _items) {
      e.dispose();
    }
    _items.clear();

    final items = (map['items'] as List?) ?? [];
    if (items.isEmpty) {
      _items.add(_ItemCtrls());
    } else {
      for (final it in items) {
        final row = _ItemCtrls();
        final m = it as Map<String, dynamic>;
        row.desc.text = (m['desc'] ?? '').toString();
        row.qty.text = (m['qty'] ?? '1').toString();
        row.price.text = (m['price'] ?? '0.00').toString();
        _items.add(row);
      }
    }

    setState(() {});
    _saveDraft();
  }

  String _jsonPretty(Map<String, dynamic> map) =>
      const JsonEncoder.withIndent('  ').convert(map);

  Future<void> _showExportDialog() async {
    final t = widget.t;
    final jsonText = _jsonPretty(_currentTemplateMap());
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(t('export_template')),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SingleChildScrollView(
            child: Text(jsonText, style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () async {
              final nav = Navigator.of(context);
              await Clipboard.setData(ClipboardData(text: jsonText));
              if (mounted) nav.pop();
            },
            child: Text(t('copy')),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog() async {
    final t = widget.t;
    final ctrl = TextEditingController();
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(t('import_template')),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: t('paste_json_here'),
            maxLines: 12,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('close')),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              try {
                final map = jsonDecode(ctrl.text) as Map<String, dynamic>;
                _applyTemplateMap(map);
                Navigator.of(context).pop();
                _showInfo(t('template_loaded'));
              } catch (_) {
                Navigator.of(context).pop();
                _showInfo(t('invalid_json'));
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ---------------- Company Profile JSON ----------------
  Map<String, dynamic> _profileMap() => {
        'seller': _sellerCtrl.text,
        'brand': _brandCtrl.text,
        'currency': _currencyCtrl.text,
        'taxRate': _taxRateCtrl.text,
        'address': _addrCtrl.text,
        'phone': _phoneCtrl.text,
        'email': _emailCtrl.text,
        'website': _websiteCtrl.text,
        'taxId': _taxIdCtrl.text,
        'iban': _ibanCtrl.text,
        'footerNote': _footerNoteCtrl.text,
        'logoB64': _logoBytes == null ? null : base64Encode(_logoBytes!),
        'signatureB64': _signatureBytes == null ? null : base64Encode(_signatureBytes!),
      };

  void _applyProfileMap(Map<String, dynamic> map, {bool callSetState = true}) {
    _sellerCtrl.text = (map['seller'] ?? _sellerCtrl.text).toString();
    _brandCtrl.text = (map['brand'] ?? _brandCtrl.text).toString();
    _currencyCtrl.text = (map['currency'] ?? _currencyCtrl.text).toString();
    _taxRateCtrl.text = (map['taxRate'] ?? _taxRateCtrl.text).toString();

    _addrCtrl.text = (map['address'] ?? _addrCtrl.text).toString();
    _phoneCtrl.text = (map['phone'] ?? _phoneCtrl.text).toString();
    _emailCtrl.text = (map['email'] ?? _emailCtrl.text).toString();
    _websiteCtrl.text = (map['website'] ?? _websiteCtrl.text).toString();
    _taxIdCtrl.text = (map['taxId'] ?? _taxIdCtrl.text).toString();
    _ibanCtrl.text = (map['iban'] ?? _ibanCtrl.text).toString();
    _footerNoteCtrl.text = (map['footerNote'] ?? _footerNoteCtrl.text).toString();

    final b64 = map['logoB64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      try {
        _logoBytes = base64Decode(b64);
      } catch (_) {}
    }

    final s64 = map['signatureB64']?.toString();
    if (s64 != null && s64.isNotEmpty) {
      try {
        _signatureBytes = base64Decode(s64);
      } catch (_) {}
    }

    if (callSetState) {
      setState(() {});
      _saveDraft();
    }
  }

  Future<void> _exportProfileDialog() async {
    final t = widget.t;
    final jsonText = _jsonPretty(_profileMap());
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(t('profile_export')),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SingleChildScrollView(
            child: Text(jsonText, style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () async {
              final nav = Navigator.of(context);
              await Clipboard.setData(ClipboardData(text: jsonText));
              if (mounted) nav.pop();
            },
            child: Text(t('copy')),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _importProfileDialog() async {
    final t = widget.t;
    final ctrl = TextEditingController();
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(t('profile_import')),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: t('paste_json_here'),
            maxLines: 12,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('close')),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              try {
                final map = jsonDecode(ctrl.text) as Map<String, dynamic>;
                _applyProfileMap(map);
                Navigator.of(context).pop();
                _showInfo(t('template_loaded'));
              } catch (_) {
                Navigator.of(context).pop();
                _showInfo(t('invalid_json'));
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ---------------- CSV helpers ----------------

  Future<void> _exportCsv() async {
    final rows = <List<dynamic>>[];
    rows.add(['description', 'qty', 'price']);
    for (final it in _items) {
      final q = int.tryParse(it.qty.text) ?? 0;
      final p = double.tryParse(it.price.text.replaceAll(',', '.')) ?? 0.0;
      rows.add([it.desc.text, q, p]);
    }
    // totals (optional lines)
    final totals = _computeTotals();
    rows.add([]);
    rows.add(['subtotal', '', totals.subtotal]);
    rows.add(['discount', '', -totals.discount]);
    rows.add(['tax', '', totals.tax]);
    rows.add(['delivery', '', totals.delivery]);
    rows.add(['total', '', totals.total]);

    final csvStr = const csv.ListToCsvConverter().convert(rows);
    _downloadTextFile(_buildCsvFileName(), csvStr, 'text/csv');
  }

Future<void> _importCsv() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv'],
    withData: true,
  );
  final bytes = res?.files.single.bytes;
  if (bytes == null || bytes.isEmpty) return;

  final content = utf8.decode(bytes);

  // Explicit type: no row casts needed later.
  final List<List<dynamic>> table = const csv.CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false,
  ).convert(content);

  if (table.isEmpty) {
    _showInfo(widget.t('invalid_csv'));
    return;
  }

  // First row = headers
  final headers = table.first.map((e) => e.toString()).toList();
  final lower = headers.map((e) => e.toLowerCase().trim()).toList();

  int idxDesc = lower.indexOf('description');
  int idxQty = lower.indexOf('qty');
  int idxPrice = lower.indexOf('price');

  // Manual mapping if not auto-detected
  if (idxDesc == -1 || idxQty == -1 || idxPrice == -1) {
    idxDesc = await _pickCsvColumn(headers, widget.t('col_description')) ?? 0;
    idxQty = await _pickCsvColumn(headers, widget.t('col_qty')) ?? 1;
    idxPrice = await _pickCsvColumn(headers, widget.t('col_price')) ?? 2;
  }

  final newItems = <_ItemCtrls>[];

  // Iterate rows after header (no cast)
  for (int r = 1; r < table.length; r++) {
    final row = table[r];
    if (row.isEmpty) continue;

    final String desc = (idxDesc < row.length ? row[idxDesc].toString() : '').trim();
    if (desc.isEmpty) continue;

    final String qtyStr = idxQty < row.length ? row[idxQty].toString() : '0';
    final String priceStr = idxPrice < row.length ? row[idxPrice].toString() : '0';

    final it = _ItemCtrls()
      ..desc.text = desc
      ..qty.text = qtyStr
      ..price.text = priceStr;

    newItems.add(it);
  }

  if (newItems.isEmpty) {
    _showInfo(widget.t('invalid_csv'));
    return;
  }

  // replace items
  for (final e in _items) {
    e.dispose();
  }
  setState(() {
    _items
      ..clear()
      ..addAll(newItems);
  });
  _saveDraft();
  _showInfo(widget.t('csv_loaded'));
}
  Future<int?> _pickCsvColumn(List<String> headers, String title) async {
    int selected = 0;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        height: 280,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    child: Text(widget.t('close')),
                  ),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    child: Text(widget.t('ok')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                itemExtent: 36,
                onSelectedItemChanged: (i) => selected = i,
                children: [
                  for (final h in headers) Center(child: Text(h)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return selected;
  }

  // Data-URL download (أبسط وأضمن للويب)
  void _downloadTextFile(String filename, String text, String mime) {
    try {
      final url = 'data:$mime;charset=utf-8,${Uri.encodeComponent(text)}';
      final a = web.document.createElement('a') as web.HTMLAnchorElement;
      a.href = url;
      a.download = filename;
      web.document.body?.append(a);
      a.click();
      a.remove();
    } catch (_) {}
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final totals = _computeTotals();
    final currency = _currencyCtrl.text;
    final loc = _userLocale(context);

    return SafeArea(
      child: CupertinoScrollbar(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      t('app_title'),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Template export/import
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            onPressed: _showExportDialog,
                            child: Text(t('export_template')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CupertinoButton(
                            onPressed: _showImportDialog,
                            child: Text(t('import_template')),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Seller / Buyer
                    _sectionCard(
                      child: Column(
                        children: [
                          _fieldRow(
                            label: t('seller'),
                            controller: _sellerCtrl,
                            placeholder: t('seller_placeholder'),
                          ),
                          const SizedBox(height: 8),
                          _fieldRow(
                            label: t('buyer'),
                            controller: _buyerCtrl,
                            placeholder: t('buyer_placeholder'),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Branding + meta + settings
                    _sectionCard(
                      child: Column(
                        children: [
                          _fieldRow(
                            label: t('brand'),
                            controller: _brandCtrl,
                            placeholder: t('brand_placeholder'),
                          ),
                          const SizedBox(height: 8),
                          _fieldRow(
                            label: t('doc_title'),
                            controller: _docTitleCtrl,
                            placeholder: t('doc_title_placeholder'),
                          ),
                          const SizedBox(height: 8),
                          _fieldRow(
                            label: t('invoice_no'),
                            controller: _invoiceNoCtrl,
                            placeholder: t('invoice_no_placeholder'),
                          ),
                          const SizedBox(height: 8),

                          // Auto-number UI
                          Row(
                            children: [
                              _miniField(
                                t('prefix'),
                                _invPrefixCtrl,
                                width: 140,
                                placeholder: 'INV-',
                                onChanged: (_) => _saveDraft(),
                              ),
                              const SizedBox(width: 12),
                              _miniField(
                                t('pad'),
                                _invPadCtrl,
                                width: 90,
                                placeholder: '3',
                                keyboardType: const TextInputType.numberWithOptions(),
                                onChanged: (_) => _saveDraft(),
                              ),
                              const SizedBox(width: 12),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                onPressed: _nextInvoiceNumber,
                                child: Text(t('next_number')),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),
                          _row(
                            t('date'),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              onPressed: () => _pickDate(context),
                              child: Text(_fmtDateL(_invoiceDate, loc)),
                            ),
                          ),
                          const SizedBox(height: 8),

                          _twoCols(
                            left: _miniField(
                              t('currency'),
                              _currencyCtrl,
                              width: 120,
                              placeholder: t('currency_placeholder'),
                              onChanged: (_) {
                                setState(() {});
                                _saveDraft();
                              },
                            ),
                            right: _miniField(
                              t('tax_percent'),
                              _taxRateCtrl,
                              width: 120,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              placeholder: '0',
                              onChanged: (_) {
                                setState(() {});
                                _saveDraft();
                              },
                            ),
                          ),

                          const SizedBox(height: 12),

                          _row(
                            t('page_size'),
                            CupertinoSlidingSegmentedControl<String>(
                              groupValue: _pageSize,
                              children: {
                                'A4': Text(t('a4')),
                                'Letter': Text(t('letter')),
                              },
                              onValueChanged: (v) {
                                if (v == null) return;
                                setState(() => _pageSize = v);
                                _saveDraft();
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          _row(
                            t('orientation'),
                            CupertinoSlidingSegmentedControl<bool>(
                              groupValue: _landscape,
                              children: {
                                false: Text(t('portrait')),
                                true: Text(t('landscape')),
                              },
                              onValueChanged: (v) {
                                if (v == null) return;
                                setState(() => _landscape = v);
                                _saveDraft();
                              },
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Logo row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(t('logo'), style: const TextStyle(fontSize: 14)),
                              Row(
                                children: [
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    onPressed: _pickLogo,
                                    child: Text(t('upload_logo')),
                                  ),
                                  if (_logoBytes != null)
                                    CupertinoButton(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      onPressed: _removeLogo,
                                      child: Text(t('remove_logo')),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          if (_logoBytes != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Image.memory(_logoBytes!, height: 36),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Payments section
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t('payments'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),

                          // status selector + custom text
                          _row(
                            t('payment_status'),
                            CupertinoSlidingSegmentedControl<String>(
                              groupValue: _paymentStatus,
                              children: {
                                'paid': Text(t('status_paid')),
                                'unpaid': Text(t('status_unpaid')),
                                'pay_later': Text(t('status_pay_later')),
                                'cod': Text(t('status_cod')),
                              },
                              onValueChanged: (v) {
                                if (v == null) return;
                                setState(() => _paymentStatus = v);
                                _saveDraft();
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          _fieldRow(
                            label: t('custom_status'),
                            controller: _paymentStatusCustomCtrl,
                            placeholder: t('optional'),
                          ),
                          const SizedBox(height: 8),
                          _twoCols(
                            left: _miniField(
                              t('payment_method'),
                              _paymentMethodCtrl,
                              width: 220,
                              placeholder: 'Bank transfer / Cash',
                              onChanged: (_) => _saveDraft(),
                            ),
                            right: _miniField(
                              t('payment_terms'),
                              _paymentTermsCtrl,
                              width: 220,
                              placeholder: 'Net 30',
                              onChanged: (_) => _saveDraft(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _row(
                            t('due_date'),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              onPressed: _pickDueDate,
                              child: Text(_dueDate == null ? t('none') : _fmtDateL(_dueDate!, loc)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Company Profile (import/export JSON)
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t('company_profile'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          _fieldRow(label: t('address'), controller: _addrCtrl, placeholder: t('address_placeholder')),
                          const SizedBox(height: 8),
                          _twoCols(
                            left: _miniField(t('phone'), _phoneCtrl, width: 180, placeholder: '+974 5555 5555', onChanged: (_) => _saveDraft()),
                            right: _miniField(t('email'), _emailCtrl, width: 220, placeholder: 'contact@company.com', onChanged: (_) => _saveDraft()),
                          ),
                          const SizedBox(height: 8),
                          _twoCols(
                            left: _miniField(t('website'), _websiteCtrl, width: 220, placeholder: 'https://example.com', onChanged: (_) => _saveDraft()),
                            right: _miniField(t('tax_id'), _taxIdCtrl, width: 180, placeholder: 'VAT / Tax ID', onChanged: (_) => _saveDraft()),
                          ),
                          const SizedBox(height: 8),
                          _twoCols(
                            left: _miniField(t('iban'), _ibanCtrl, width: 260, placeholder: 'IBAN', onChanged: (_) => _saveDraft()),
                            right: _miniField(t('footer_note'), _footerNoteCtrl, width: 220, placeholder: t('footer_placeholder'), onChanged: (_) => _saveDraft()),
                          ),
                          const SizedBox(height: 12),

                          // Signature (upload image)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(t('signature'), style: const TextStyle(fontSize: 14)),
                              Row(
                                children: [
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    onPressed: _pickSignature,
                                    child: Text(t('upload_signature')),
                                  ),
                                  if (_signatureBytes != null)
                                    CupertinoButton(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      onPressed: _removeSignature,
                                      child: Text(t('remove_signature')),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          if (_signatureBytes != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Image.memory(_signatureBytes!, height: 40),
                            ),

                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoButton(
                                  onPressed: _exportProfileDialog,
                                  child: Text(t('profile_export')),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: CupertinoButton(
                                  onPressed: _importProfileDialog,
                                  child: Text(t('profile_import')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Items
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(t('items'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                onPressed: _addItem,
                                child: Text(t('add_item')),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (int i = 0; i < _items.length; i++) _itemCard(i, currency, t),

                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoButton(
                                  onPressed: _exportCsv,
                                  child: Text(t('export_csv')),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: CupertinoButton(
                                  onPressed: _importCsv,
                                  child: Text(t('import_csv')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (kIsWeb)
                      const AdInArticleWeb(adSlot: kAdSlotArticle1, height: 280),

                    const SizedBox(height: 12),

                    // Totals (+ inputs for discount & delivery)
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _twoCols(
                            left: _miniField(
                              t('discount_percent'),
                              _discountCtrl,
                              width: 160,
                              placeholder: '0',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) {
                                setState(() {});
                                _saveDraft();
                              },
                            ),
                            right: _miniField(
                              t('delivery_charge'),
                              _deliveryCtrl,
                              width: 180,
                              placeholder: '0',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) {
                                setState(() {});
                                _saveDraft();
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          _totalRow(t('subtotal'), totals.subtotal, currency),
                          const SizedBox(height: 6),
                          _totalRow(t('discount_percent'), -totals.discount, currency),
                          const SizedBox(height: 6),
                          _totalRow(t('tax'), totals.tax, currency),
                          const SizedBox(height: 6),
                          _totalRow(t('delivery_charge'), totals.delivery, currency),
                          _cupertinoDivider(),
                          _totalRow(t('total'), totals.total, currency, isBold: true),
                        ],
                      ),
                    ),

                    if (kIsWeb)
                      const AdBannerWeb(adSlot: kAdSlotBanner1, height: 120),

                    const SizedBox(height: 16),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton.filled(
                            onPressed: () async {
                              final loc = _userLocale(context);
                              final pdfBytes = await _buildPdf(t, loc);
                              await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
                            },
                            child: Text(t('print_pdf')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CupertinoButton(
                            onPressed: () async {
                              final loc = _userLocale(context);
                              final pdfBytes = await _buildPdf(t, loc);
                              await Printing.sharePdf(bytes: pdfBytes, filename: _buildFileName());
                            },
                            child: Text(t('download_pdf')),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Build PDF ----------------
  PdfPageFormat _selectedFormat() {
    final base = _pageSize == 'A4' ? PdfPageFormat.a4 : PdfPageFormat.letter;
    return _landscape ? base.landscape : base;
  }

  String _paymentStatusText(String Function(String) t) {
    final custom = _paymentStatusCustomCtrl.text.trim();
    if (custom.isNotEmpty) return custom;
    switch (_paymentStatus) {
      case 'paid':
        return t('status_paid');
      case 'pay_later':
        return t('status_pay_later');
      case 'cod':
        return t('status_cod');
      case 'unpaid':
      default:
        return t('status_unpaid');
    }
  }

  PdfColor _paymentStatusColor() {
    switch (_paymentStatus) {
      case 'paid':
        return PdfColors.green700;
      case 'unpaid':
        return PdfColors.red700;
      case 'pay_later':
        return PdfColors.orange700;
      case 'cod':
        return PdfColors.blue700;
      default:
        return PdfColors.grey700;
    }
  }

  Future<Uint8List> _buildPdf(String Function(String) t, String locale) async {
    final doc = pw.Document();

    // Optional logo
    pw.ImageProvider? logoProvider;
    if (_logoBytes != null && _logoBytes!.isNotEmpty) {
      logoProvider = pw.MemoryImage(_logoBytes!);
    }

    // Optional signature
    pw.ImageProvider? sigProvider;
    if (_signatureBytes != null && _signatureBytes!.isNotEmpty) {
      sigProvider = pw.MemoryImage(_signatureBytes!);
    }

    final snapshot = _items.map((it) {
      final q = int.tryParse(it.qty.text) ?? 0;
      final p = double.tryParse(it.price.text.replaceAll(',', '.')) ?? 0.0;
      return {
        'desc': it.desc.text.trim(),
        'qty': q,
        'price': p,
        'lineTotal': q * p,
      };
    }).toList();

    final totals = _computeTotals();
    final currency = _currencyCtrl.text;

    // Footer lines (company info)
    final footerLines = <String>[];
    if (_addrCtrl.text.isNotEmpty) {
      footerLines.add(_addrCtrl.text);
    }
    final contacts = [
      if (_phoneCtrl.text.isNotEmpty) 'Tel: ${_phoneCtrl.text}',
      if (_emailCtrl.text.isNotEmpty) 'Email: ${_emailCtrl.text}',
      if (_websiteCtrl.text.isNotEmpty) _websiteCtrl.text,
    ].join(' | ');
    if (contacts.isNotEmpty) {
      footerLines.add(contacts);
    }
    final taxBank = [
      if (_taxIdCtrl.text.isNotEmpty) 'VAT: ${_taxIdCtrl.text}',
      if (_ibanCtrl.text.isNotEmpty) 'IBAN: ${_ibanCtrl.text}',
    ].join(' | ');
    if (taxBank.isNotEmpty) {
      footerLines.add(taxBank);
    }
    if (_footerNoteCtrl.text.isNotEmpty) {
      footerLines.add(_footerNoteCtrl.text);
    }

    // Payments block (optional)
    pw.Widget paymentsBlock() {
      final lines = <pw.Widget>[];
      final status = _paymentStatusText(t);
      lines.add(
        pw.Row(
          children: [
            pw.Text('${t('payment_status')}: ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.Text(status, style: pw.TextStyle(color: _paymentStatusColor(), fontSize: 11)),
          ],
        ),
      );
      if (_paymentMethodCtrl.text.trim().isNotEmpty) {
        lines.add(pw.Text('${t('payment_method')}: ${_paymentMethodCtrl.text.trim()}', style: const pw.TextStyle(fontSize: 10)));
      }
      if (_paymentTermsCtrl.text.trim().isNotEmpty) {
        lines.add(pw.Text('${t('payment_terms')}: ${_paymentTermsCtrl.text.trim()}', style: const pw.TextStyle(fontSize: 10)));
      }
      if (_dueDate != null) {
        lines.add(pw.Text('${t('due_date')}: ${_fmtDateL(_dueDate!, locale)}', style: const pw.TextStyle(fontSize: 10)));
      }
      return pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: lines),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: _selectedFormat(),
          margin: const pw.EdgeInsets.all(28),
        ),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoProvider != null) pw.Image(logoProvider, height: 36),
                if (logoProvider != null) pw.SizedBox(width: 12),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_brandCtrl.text.isEmpty ? ' ' : _brandCtrl.text,
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_docTitleCtrl.text.isEmpty ? ' ' : _docTitleCtrl.text,
                        style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (sigProvider != null) ...[
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 180,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      children: [
                        pw.SizedBox(height: 6),
                        pw.Image(sigProvider, height: 40, fit: pw.BoxFit.contain),
                        pw.SizedBox(height: 6),
                        pw.Divider(thickness: 0.5, color: PdfColors.grey500),
                        pw.Text(t('signature'), style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
            ],
            if (footerLines.isNotEmpty) ...[
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              for (final line in footerLines)
                pw.Text(line, style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9)),
              pw.SizedBox(height: 4),
            ],
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
            ),
          ],
        ),
        build: (context) => [
          // seller / buyer
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _cardBox([_labelValue(t('seller'), _sellerCtrl.text)])),
              pw.SizedBox(width: 12),
              pw.Expanded(child: _cardBox([_labelValue(t('buyer'), _buyerCtrl.text)])),
            ],
          ),
          pw.SizedBox(height: 10),
          _cardBox([
            _kvRow(t('invoice_no'), _invoiceNoCtrl.text),
            _kvRow(t('date'), _fmtDateL(_invoiceDate, locale)),
            _kvRow(t('currency'), _currencyCtrl.text),
            _kvRow(t('tax_percent'), _taxRateCtrl.text),
          ]),

          pw.SizedBox(height: 10),
          // payments (optional)
          if (_paymentStatusCustomCtrl.text.trim().isNotEmpty ||
              _paymentMethodCtrl.text.trim().isNotEmpty ||
              _paymentTermsCtrl.text.trim().isNotEmpty ||
              _paymentStatus.isNotEmpty ||
              _dueDate != null)
            paymentsBlock(),

          pw.SizedBox(height: 14),
          // Items table
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(5),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cellHeader(t('description')),
                  _cellHeader(t('qty')),
                  _cellHeader(t('price')),
                  _cellHeader(t('line_total')),
                ],
              ),
              ...snapshot.map((m) => pw.TableRow(children: [
                    _cell(m['desc'] as String),
                    _cell('${m['qty']}'),
                    _cell(_fmtCurrencyL(m['price'] as double, currency, locale)),
                    _cell(_fmtCurrencyL(m['lineTotal'] as double, currency, locale)),
                  ])),
            ],
          ),
          pw.SizedBox(height: 12),
          // totals card
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 280,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                children: [
                  _totRow(t('subtotal'), totals.subtotal, currency, locale: locale),
                  _totRow(t('discount_percent'), -totals.discount, currency, locale: locale),
                  _totRow(t('tax'), totals.tax, currency, locale: locale),
                  _totRow(t('delivery_charge'), totals.delivery, currency, locale: locale),
                  pw.Divider(thickness: 0.6),
                  _totRow(t('total'), totals.total, currency, bold: true, locale: locale),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------- PDF helpers ----------------
  pw.Widget _cardBox(List<pw.Widget> children) => pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
      );

  pw.Widget _labelValue(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(value.isEmpty ? '-' : value, style: const pw.TextStyle(fontSize: 10)),
        ],
      );

  pw.Widget _kvRow(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700)),
            pw.Text(v.isEmpty ? '-' : v),
          ],
        ),
      );

  pw.Widget _cellHeader(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        ),
      );

  pw.Widget _cell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text.isEmpty ? '-' : text, style: const pw.TextStyle(fontSize: 10)),
      );

  pw.Widget _totRow(String label, double value, String currency, {bool bold = false, required String locale}) {
    final style = pw.TextStyle(
      fontSize: 11,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(_fmtCurrencyL(value, currency, locale), style: style),
        ],
      ),
    );
  }

  // ---------------- File name helpers ----------------
  String _buildFileName() {
    String clean(String s) => s.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final brand = clean(_brandCtrl.text.isEmpty ? 'Invoice' : _brandCtrl.text);
    final inv = clean(_invoiceNoCtrl.text.isEmpty ? 'INV' : _invoiceNoCtrl.text);
    final date = '${_invoiceDate.year}-${_two(_invoiceDate.month)}-${_two(_invoiceDate.day)}';
    return '$brand-$inv-$date.pdf';
  }

  String _buildCsvFileName() {
    String clean(String s) => s.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final brand = clean(_brandCtrl.text.isEmpty ? 'Invoice' : _brandCtrl.text);
    final inv = clean(_invoiceNoCtrl.text.isEmpty ? 'INV' : _invoiceNoCtrl.text);
    final date = '${_invoiceDate.year}-${_two(_invoiceDate.month)}-${_two(_invoiceDate.day)}';
    return '$brand-$inv-$date.csv';
  }

  // ---------------- Common small UI helpers ----------------
  Widget _sectionCard({required Widget child}) => Container(
        decoration: _boxDecoration(),
        padding: const EdgeInsets.all(12),
        child: child,
      );

  BoxDecoration _boxDecoration() => BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(blurRadius: 12, offset: Offset(0, 4), color: Color(0x1A000000)),
        ],
      );

  Widget _row(String label, Widget trailing) => Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          trailing,
        ],
      );

  Widget _fieldRow({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    TextInputType? keyboardType,
    void Function(String)? onChanged,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 8),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: placeholder,
              keyboardType: keyboardType,
              onChanged: onChanged ?? (_) => _saveDraft(),
            ),
          ),
        ],
      );

  Widget _miniField(
    String label,
    TextEditingController controller, {
    required double width,
    String? placeholder,
    TextInputType? keyboardType,
    void Function(String)? onChanged,
  }) =>
      SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            CupertinoTextField(
              controller: controller,
              placeholder: placeholder,
              keyboardType: keyboardType,
              onChanged: onChanged ?? (_) => _saveDraft(),
            ),
          ],
        ),
      );

  Widget _twoCols({required Widget left, required Widget right}) => Row(children: [left, const SizedBox(width: 12), right]);

  Widget _totalRow(String label, double value, String currency, {bool isBold = false}) {
    final style = TextStyle(fontSize: isBold ? 16 : 14, fontWeight: isBold ? FontWeight.w600 : FontWeight.w400);
    return _row(label, Text('${value.toStringAsFixed(2)} $currency', style: style));
  }

  // ---- Item UI ----
  Widget _itemCard(int index, String currency, String Function(String) t) {
    final it = _items[index];
    final qty = int.tryParse(it.qty.text) ?? 0;
    final price = double.tryParse(it.price.text.replaceAll(',', '.')) ?? 0.0;
    final lineTotal = qty * price;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: _boxDecoration(),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _fieldRow(
              label: t('description'),
              controller: it.desc,
              placeholder: t('description_placeholder'),
              onChanged: (_) {
                setState(() {});
                _saveDraft();
              },
            ),
            const SizedBox(height: 8),
            _twoCols(
              left: _miniField(
                t('qty'),
                it.qty,
                width: 120,
                keyboardType: const TextInputType.numberWithOptions(signed: false),
                placeholder: t('qty_placeholder'),
                onChanged: (_) {
                  setState(() {});
                  _saveDraft();
                },
              ),
              right: _miniField(
                t('price'),
                it.price,
                width: 160,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                placeholder: t('price_placeholder'),
                onChanged: (_) {
                  setState(() {});
                  _saveDraft();
                },
              ),
            ),
            const SizedBox(height: 6),
            _row(t('line_total'), Text('${lineTotal.toStringAsFixed(2)} $currency')),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () => _removeItem(index),
                child: Text(t('remove')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // misc
  Future<void> _pickDate(BuildContext context) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(widget.t('ok')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _invoiceDate,
                maximumDate: DateTime(2100),
                onDateTimeChanged: (dt) {
                  setState(() => _invoiceDate = dt);
                  _saveDraft();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _two(int v) => v.toString().padLeft(2, '0');
}

class _ItemCtrls {
  final desc = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController(text: '0.00');
  void dispose() {
    desc.dispose();
    qty.dispose();
    price.dispose();
  }
}

class _Totals {
  final double subtotal;
  final double discount;
  final double delivery;
  final double tax;
  final double total;
  _Totals({required this.subtotal, required this.discount, required this.delivery, required this.tax, required this.total});
}
