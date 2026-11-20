import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

final FlutterLocalNotificationsPlugin bildirimPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const androidAyar = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initAyar = InitializationSettings(android: androidAyar);
  await bildirimPlugin.initialize(initAyar);

  final androidImpl = bildirimPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FiyatAvcisiEkrani(),
    ),
  );
}

class TakipUrunu {
  final String baslik;
  final String platform;
  final String url;
  final double bazFiyat;
  double? sonFiyat;
  double? indirimOrani;
  String durum;

  TakipUrunu({
    required this.baslik,
    required this.platform,
    required this.url,
    required this.bazFiyat,
    this.sonFiyat,
    this.indirimOrani,
    this.durum = 'Bekliyor',
  });
}

class FiyatAvcisiEkrani extends StatefulWidget {
  const FiyatAvcisiEkrani({super.key});

  @override
  State<FiyatAvcisiEkrani> createState() => _FiyatAvcisiEkraniState();
}

class _FiyatAvcisiEkraniState extends State<FiyatAvcisiEkrani> {
  final urlCtrl = TextEditingController();
  final bazFiyatCtrl = TextEditingController();
  String seciliPlatform = 'Trendyol';
  bool otoTaramaAktif = true;
  Timer? zamanlayici;

  final List<TakipUrunu> liste = [];

  @override
  void initState() {
    super.initState();
    zamanlayici = Timer.periodic(const Duration(seconds: 60), (_) {
      if (otoTaramaAktif && liste.isNotEmpty) {
        tumunuKontrolEt();
      }
    });
  }

  @override
  void dispose() {
    zamanlayici?.cancel();
    urlCtrl.dispose();
    bazFiyatCtrl.dispose();
    super.dispose();
  }

  Future<void> bildirimGonder(String baslik, String icerik) async {
    const androidDetay = AndroidNotificationDetails(
      'indirim_70_kanal',
      '%70+ Indirim Uyarisi',
      channelDescription: '%70 ve uzeri fiyat dususu bildirimleri',
      importance: Importance.max,
      priority: Priority.high,
    );
    const detay = NotificationDetails(android: androidDetay);
    await bildirimPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      baslik,
      icerik,
      detay,
    );
  }

  double? sayfaFiyatiBul(String html) {
    final desenler = [
      RegExp(r'"price"\s*:\s*"?(\d+(?:[.,]\d{1,2})?)"?'),
      RegExp(r'(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?)\s*TL'),
    ];

    final bulunanlar = <double>[];
    for (final r in desenler) {
      for (final m in r.allMatches(html)) {
        final raw = m.group(1);
        if (raw == null) continue;
        final temiz = raw.replaceAll('.', '').replaceAll(',', '.');
        final val = double.tryParse(temiz);
        if (val != null && val > 0 && val < 10000000) {
          bulunanlar.add(val);
        }
      }
      if (bulunanlar.isNotEmpty) break;
    }

    if (bulunanlar.isEmpty) return null;
    bulunanlar.sort();
    return bulunanlar.first;
  }

  Future<void> urunKontrolEt(TakipUrunu urun) async {
    setState(() => urun.durum = 'Kontrol ediliyor...');
    try {
      final resp = await http.get(
        Uri.parse(urun.url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 Chrome/126.0.0.0 Mobile Safari/537.36',
          'Accept-Language': 'tr-TR,tr;q=0.9',
        },
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final yeniFiyat = sayfaFiyatiBul(resp.body);
        if (yeniFiyat != null && urun.bazFiyat > 0) {
          final oran = ((urun.bazFiyat - yeniFiyat) / urun.bazFiyat) * 100;
          setState(() {
            urun.sonFiyat = yeniFiyat;
            urun.indirimOrani = oran;
            urun.durum =
                'Fiyat: ${yeniFiyat.toStringAsFixed(0)} TL (%${oran.toStringAsFixed(1)} indirim)';
          });

          if (oran >= 70.0) {
            await bildirimGonder(
              '%${oran.toStringAsFixed(0)} INDIRIM (${urun.platform})',
              '${urun.baslik} -> ${yeniFiyat.toStringAsFixed(0)} TL',
            );
          }
          return;
        }
      }
      setState(() =>
          urun.durum = 'Sayfa fiyat okumaya kapali (Kod: ${resp.statusCode})');
    } catch (_) {
      setState(() => urun.durum = 'Baglanti/engel nedeniyle okunamadi');
    }
  }

  Future<void> tumunuKontrolEt() async {
    for (final u in List<TakipUrunu>.from(liste)) {
      await urunKontrolEt(u);
    }
  }

  Future<void> urunEkleVeTara() async {
    final link = urlCtrl.text.trim();
    final baz =
        double.tryParse(bazFiyatCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (!link.startsWith('http') || baz <= 0) return;

    final yeniUrun = TakipUrunu(
      baslik: '$seciliPlatform Urunu',
      platform: seciliPlatform,
      url: link,
      bazFiyat: baz,
    );

    setState(() {
      liste.insert(0, yeniUrun);
      urlCtrl.clear();
      bazFiyatCtrl.clear();
    });

    await urunKontrolEt(yeniUrun);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiyat Avcisi (%70+ Bildirim)'),
        actions: [
          Switch(
            value: otoTaramaAktif,
            onChanged: (v) => setState(() => otoTaramaAktif = v),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: seciliPlatform,
                  items: const [
                    DropdownMenuItem(value: 'Trendyol', child: Text('Trendyol')),
                    DropdownMenuItem(
                        value: 'Hepsiburada', child: Text('Hepsiburada')),
                    DropdownMenuItem(value: 'Amazon', child: Text('Amazon')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => seciliPlatform = v);
                  },
                  decoration: const InputDecoration(labelText: 'Platform'),
                ),
                TextField(
                  controller: urlCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Urun Linki (https://...)'),
                ),
                TextField(
                  controller: bazFiyatCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Normal Fiyat (TL)'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: urunEkleVeTara,
                        child: const Text('Listeye Ekle'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: tumunuKontrolEt,
                      child: const Text('Simdi Tara'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: liste.length,
              itemBuilder: (context, i) {
                final item = liste[i];
                final firsat = (item.indirimOrani ?? 0) >= 70.0;
                return ListTile(
                  leading: Icon(
                    firsat ? Icons.notifications_active : Icons.radar,
                    color: firsat ? Colors.red : Colors.blueGrey,
                  ),
                  title: Text('${item.platform} - ${item.baslik}'),
                  subtitle: Text('${item.durum}\n${item.url}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () => Share.share(
                      '${item.platform} %70+ Firsat!\n${item.url}',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
