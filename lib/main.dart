import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'invoice_form.dart';

/// Lightweight JSON-based localizations (EN/DE)
class AppLocalizations {
  final Locale locale;
  late final Map<String, dynamic> _values;

  AppLocalizations(this.locale);

  static const supportedLocales = [Locale('en'), Locale('de')];

  static AppLocalizations of(BuildContext context) {
    final l = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l == null) {
      throw FlutterError('AppLocalizations not found in context');
    }
    return l;
  }

  Future<void> load() async {
    final code = (locale.languageCode == 'de') ? 'de' : 'en';
    final jsonStr = await rootBundle.loadString('assets/i18n/$code.json');
    _values = json.decode(jsonStr) as Map<String, dynamic>;
  }

  String t(String key) => _values[key]?.toString() ?? key;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'de'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final loc = AppLocalizations(locale);
    await loc.load();
    return loc;
  }

  @override
  bool shouldReload(LocalizationsDelegate<AppLocalizations> old) => false;
}

void main() {
  runApp(const InvoxiApp());
}

class InvoxiApp extends StatefulWidget {
  const InvoxiApp({super.key});

  @override
  State<InvoxiApp> createState() => _InvoxiAppState();
}

class _InvoxiAppState extends State<InvoxiApp> {
  Locale _locale = const Locale('en');

  void _setLocale(String code) {
    setState(() => _locale = Locale(code));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        _AppLocalizationsDelegate(),
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: HomePage(onLangChange: _setLocale),
    );
  }
}

class HomePage extends StatelessWidget {
  final void Function(String code) onLangChange;

  const HomePage({super.key, required this.onLangChange});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final lang = Localizations.localeOf(context).languageCode; // ← مصدر الحقيقة

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t('app_title')),
        trailing: SizedBox(
          width: 140,
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: lang, // ← يتحدّث تلقائيًا بعد تغيير اللغة
            children: const {'en': Text('EN'), 'de': Text('DE')},
            onValueChanged: (v) {
              if (v != null) onLangChange(v);
            },
          ),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              t('welcome'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => InvoicePage(onLangChange: onLangChange),
                  ),
                );
              },
              child: Text(t('start')),
            ),
          ],
        ),
      ),
    );
  }
}

class InvoicePage extends StatelessWidget {
  final void Function(String code) onLangChange;

  const InvoicePage({super.key, required this.onLangChange});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final lang = Localizations.localeOf(context).languageCode; // ← هنا أيضًا

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        previousPageTitle: t('back'),
        middle: Text(t('app_title')),
        trailing: SizedBox(
          width: 140,
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: lang,
            children: const {'en': Text('EN'), 'de': Text('DE')},
            onValueChanged: (v) {
              if (v != null) onLangChange(v);
            },
          ),
        ),
      ),
      child: InvoiceForm(t: t),
    );
  }
}
